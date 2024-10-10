// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin Contracts
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20 {
    // Standard ERC20 functions
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

interface IRegistry {
    function hasCompliance(
        bytes32 compliance,
        address user
    ) external view returns (bool);
}

contract LoanPool is ReentrancyGuard {
    using SafeMath for uint256;

    // Enums
    enum LoanStatus {
        OpenForFunding,
        Funded,
        FundingFailed,
        Active,
        PreDefault,
        Defaulted,
        Closed
    }

    // Structs
    struct LoanParameters {
        uint256 amountNeeded;
        uint256 borrowerRate;
        uint256 platformRate;
        uint256 loanTermMonths;
        uint256 fundingDeadline;
        uint256 setupFee;
    }

    struct Addresses {
        address borrower;
        address escrowAdmin;
        address fundingToken;
        address protocolWallet;
        address reserveFundAddress;
    }

    struct ComplianceInfo {
        bool kycRequired;
        address registry;
        bytes32 compliance;
    }

    struct MetadataURIs {
        string poolMetadataURI;
        string loanMetadataURI;
    }

    struct Investor {
        uint256 amountFunded;
        uint256 amountWithdrawn;
        bool refunded;
    }

    // Variables
    address public borrower;
    address public escrowAdmin;
    IERC20 public fundingToken;
    LoanStatus public status;

    uint256 public amountNeeded; // Principal amount needed
    uint256 public totalFunded;
    uint256 public totalRepaid;
    uint256 public borrowerRate; // Total annual interest rate in basis points (e.g., 3500 = 35%)
    uint256 public platformRate; // Platform's annual interest rate in basis points
    uint256 public investorRate; // Calculated as borrowerRate - platformRate
    uint256 public loanTermMonths;
    uint256 public fundingDeadline; // Timestamp when funding ends
    uint256 public loanStartDate;
    uint256 public loanFundedDate;
    uint256 public totalPaymentsMade;
    uint256 public setupFee; // Amount to be transferred to protocol wallet upon activation
    address public protocolWallet; // Address of the protocol wallet
    address public reserveFundAddress; // Address of the reserve fund
    bool public kycRequired; // Indicates if KYC is required
    address public registry; // Address of the compliance registry
    bytes32 public compliance; // Compliance identifier

    string public poolMetadataURI;
    string public loanMetadataURI;

    mapping(address => Investor) public investors;
    address[] public investorList;

    // Constants
    uint256 constant ACTIVATION_DEADLINE = 7 days;
    uint256 constant PAYMENT_INTERVAL = 30 days;
    uint256 constant GRACE_PERIOD = 14 days;
    uint256 constant RESERVE_FUND_PERCENT = 500; // 5% in basis points
    uint256 constant SUCCESS_FEE_PERCENT = 300; // 3% in basis points

    // Events
    event Funded(address indexed investor, uint256 amount);
    event FundingClosed();
    event FundingFailed();
    event FundingStoppedByAdmin();
    event LoanActivated();
    event RepaymentMade(uint256 amount);
    event PaymentMissed();
    event LoanDefaulted();
    event Claimed(address indexed investor, uint256 amount);
    event Refunded(address indexed investor, uint256 amount);
    event LoanClosed();
    event EarlyRepaid(uint256 amount, uint256 penalty);
    event InvestorAddressChanged(
        address indexed oldAddress,
        address indexed newAddress
    );

    // Modifiers
    modifier onlyBorrower() {
        require(msg.sender == borrower, "Only borrower can call this function");
        _;
    }

    modifier onlyEscrowAdmin() {
        require(
            msg.sender == escrowAdmin,
            "Only escrow admin can call this function"
        );
        _;
    }

    modifier inStatus(LoanStatus _status) {
        require(status == _status, "Invalid loan status");
        _;
    }

    modifier updateStatus() {
        _updateLoanStatus();
        _;
    }

    // Constructor
    constructor(
        Addresses memory _addresses,
        LoanParameters memory _loanParams,
        ComplianceInfo memory _complianceInfo,
        MetadataURIs memory _metadataURIs
    ) {
        // Validate addresses
        require(_addresses.borrower != address(0), "Invalid borrower address");
        require(
            _addresses.escrowAdmin != address(0),
            "Invalid escrow admin address"
        );
        require(
            _addresses.fundingToken != address(0),
            "Invalid funding token address"
        );
        require(
            _addresses.protocolWallet != address(0),
            "Invalid protocol wallet address"
        );
        require(
            _addresses.reserveFundAddress != address(0),
            "Invalid reserve fund address"
        );

        // Validate loan parameters
        require(
            _loanParams.amountNeeded > 0,
            "Amount needed must be greater than zero"
        );
        require(
            _loanParams.loanTermMonths > 0,
            "Loan term must be at least 1 month"
        );
        require(
            _loanParams.fundingDeadline > block.timestamp,
            "Funding deadline must be in the future"
        );
        require(
            _loanParams.borrowerRate > _loanParams.platformRate,
            "Borrower rate must be greater than platform rate"
        );

        // Set addresses
        borrower = _addresses.borrower;
        escrowAdmin = _addresses.escrowAdmin;
        fundingToken = IERC20(_addresses.fundingToken);
        protocolWallet = _addresses.protocolWallet;
        reserveFundAddress = _addresses.reserveFundAddress;

        // Set loan parameters
        amountNeeded = _loanParams.amountNeeded;
        borrowerRate = _loanParams.borrowerRate;
        platformRate = _loanParams.platformRate;
        investorRate = borrowerRate.sub(platformRate);
        loanTermMonths = _loanParams.loanTermMonths;
        fundingDeadline = _loanParams.fundingDeadline;
        setupFee = _loanParams.setupFee;

        // Set compliance info
        kycRequired = _complianceInfo.kycRequired;
        registry = _complianceInfo.registry;
        compliance = _complianceInfo.compliance;

        // Set metadata URIs
        poolMetadataURI = _metadataURIs.poolMetadataURI;
        loanMetadataURI = _metadataURIs.loanMetadataURI;

        // Initial status
        status = LoanStatus.OpenForFunding;
    }

    // Investor functions
    function fund(
        uint256 _amount
    ) external nonReentrant inStatus(LoanStatus.OpenForFunding) updateStatus {
        require(block.timestamp <= fundingDeadline, "Funding period has ended");
        require(msg.sender != borrower, "Borrower cannot fund their own loan");
        require(_amount > 0, "Funding amount must be greater than zero");

        // KYC Compliance Check
        if (kycRequired) {
            require(registry != address(0), "Registry address is not set");
            bool compliant = IRegistry(registry).hasCompliance(
                compliance,
                msg.sender
            );
            require(
                compliant,
                "Investor does not meet compliance requirements"
            );
        }

        uint256 remainingAmount = amountNeeded.sub(totalFunded);
        require(remainingAmount > 0, "Funding goal already reached");

        uint256 amountAccepted = _amount;
        if (_amount > remainingAmount) {
            amountAccepted = remainingAmount;
        }

        // Transfer tokens from investor to this contract
        require(
            fundingToken.transferFrom(
                msg.sender,
                address(this),
                amountAccepted
            ),
            "Token transfer failed"
        );

        // Update state before external call
        if (investors[msg.sender].amountFunded == 0) {
            investorList.push(msg.sender);
        }
        investors[msg.sender].amountFunded = investors[msg.sender]
            .amountFunded
            .add(amountAccepted);
        totalFunded = totalFunded.add(amountAccepted);

        emit Funded(msg.sender, amountAccepted);

        // Check if funding goal is met
        if (totalFunded >= amountNeeded) {
            status = LoanStatus.Funded;
            loanFundedDate = block.timestamp; // Record the date when funding is complete
            emit FundingClosed();
        }

        // Refund excess amount if any
        if (_amount > amountAccepted) {
            uint256 refundAmount = _amount.sub(amountAccepted);
            require(
                fundingToken.transfer(msg.sender, refundAmount),
                "Refund transfer failed"
            );
        }
    }

    // Function to check funding status based on deadlines
    function _updateLoanStatus() internal {
        // Check if funding deadline has passed
        if (
            status == LoanStatus.OpenForFunding &&
            block.timestamp > fundingDeadline
        ) {
            if (totalFunded >= amountNeeded) {
                status = LoanStatus.Funded;
                loanFundedDate = block.timestamp; // Record the date when funding is complete
                emit FundingClosed();
            } else {
                status = LoanStatus.FundingFailed;
                emit FundingFailed();
            }
        }

        // Check if borrower failed to activate the loan within 7 days after funding
        if (status == LoanStatus.Funded) {
            if (block.timestamp > loanFundedDate.add(ACTIVATION_DEADLINE)) {
                status = LoanStatus.FundingFailed;
                emit FundingFailed();
            }
        }

        // Check for payment defaults
        if (status == LoanStatus.Active) {
            uint256 expectedPaymentDate = loanStartDate.add(
                totalPaymentsMade.mul(PAYMENT_INTERVAL)
            );
            if (block.timestamp > expectedPaymentDate.add(GRACE_PERIOD)) {
                if (
                    block.timestamp <=
                    expectedPaymentDate.add(GRACE_PERIOD.mul(2))
                ) {
                    // Enter PreDefault status and add penalty
                    status = LoanStatus.PreDefault;
                    uint256 penalty = calculateDefaultPenalty();
                    totalRepaid = totalRepaid.add(penalty);
                    emit PaymentMissed();
                } else {
                    // Enter Defaulted status
                    status = LoanStatus.Defaulted;
                    emit LoanDefaulted();
                }
            }
        }
    }

    // Borrower functions
    function activateLoan()
        external
        onlyBorrower
        inStatus(LoanStatus.Funded)
        nonReentrant
        updateStatus
    {
        require(status == LoanStatus.Funded, "Loan is not in Funded status");

        // Calculate fees
        uint256 reserveFundAmount = amountNeeded.mul(RESERVE_FUND_PERCENT).div(
            10000
        );
        uint256 successFeeAmount = amountNeeded.mul(SUCCESS_FEE_PERCENT).div(
            10000
        );

        // Transfer setup fee to protocol wallet
        if (setupFee > 0) {
            require(
                fundingToken.transfer(protocolWallet, setupFee),
                "Setup fee transfer failed"
            );
        }

        // Transfer reserve fund amount
        require(
            fundingToken.transfer(reserveFundAddress, reserveFundAmount),
            "Reserve fund transfer failed"
        );

        // Transfer success fee to protocol wallet
        require(
            fundingToken.transfer(protocolWallet, successFeeAmount),
            "Success fee transfer failed"
        );

        // Transfer remaining funds to borrower
        uint256 amountToBorrower = totalFunded
            .sub(reserveFundAmount)
            .sub(setupFee)
            .sub(successFeeAmount);
        require(
            fundingToken.transfer(borrower, amountToBorrower),
            "Transfer to borrower failed"
        );

        status = LoanStatus.Active;
        loanStartDate = block.timestamp;
        totalPaymentsMade = 0;

        emit LoanActivated();
    }

    function repay() external onlyBorrower nonReentrant updateStatus {
        require(
            status == LoanStatus.Active || status == LoanStatus.PreDefault,
            "Loan is not active or in pre-default"
        );

        uint256 paymentAmount = getNextPaymentAmount();

        // Transfer repayment amount to this contract
        require(
            fundingToken.transferFrom(msg.sender, address(this), paymentAmount),
            "Token transfer failed"
        );

        totalRepaid = totalRepaid.add(paymentAmount);
        totalPaymentsMade = totalPaymentsMade.add(1);

        // Reset status if in PreDefault
        if (status == LoanStatus.PreDefault) {
            status = LoanStatus.Active;
        }

        emit RepaymentMade(paymentAmount);

        // Check if loan is fully repaid
        if (totalPaymentsMade >= loanTermMonths) {
            status = LoanStatus.Closed;
            emit LoanClosed();
        }
    }

    function earlyRepay() external onlyBorrower nonReentrant updateStatus {
        require(
            status == LoanStatus.Active || status == LoanStatus.PreDefault,
            "Loan is not active or in pre-default"
        );

        uint256 outstandingPrincipal = getOutstandingPrincipal();
        uint256 penalty = calculateEarlyRepaymentPenalty();

        uint256 totalAmount = outstandingPrincipal.add(penalty);

        // Transfer repayment amount + penalty to this contract
        require(
            fundingToken.transferFrom(msg.sender, address(this), totalAmount),
            "Token transfer failed"
        );

        totalRepaid = totalRepaid.add(outstandingPrincipal);
        totalPaymentsMade = loanTermMonths; // Mark all payments as made

        emit EarlyRepaid(outstandingPrincipal, penalty);

        // Close the loan
        status = LoanStatus.Closed;
        emit LoanClosed();
    }

    // Investor claim function
    function claim() external nonReentrant updateStatus {
        require(
            status == LoanStatus.Active || status == LoanStatus.Closed,
            "Loan is not active or closed"
        );
        Investor storage investor = investors[msg.sender];
        require(investor.amountFunded > 0, "Not an investor");

        uint256 totalOwed = calculateInvestorOwed(msg.sender);
        uint256 amountToWithdraw = totalOwed.sub(investor.amountWithdrawn);
        require(amountToWithdraw > 0, "Nothing to claim");

        investor.amountWithdrawn = investor.amountWithdrawn.add(
            amountToWithdraw
        );

        // Transfer tokens to investor
        require(
            fundingToken.transfer(msg.sender, amountToWithdraw),
            "Token transfer failed"
        );

        emit Claimed(msg.sender, amountToWithdraw);
    }

    // Investor refund function
    function refund() external nonReentrant updateStatus {
        require(status == LoanStatus.FundingFailed, "Funding did not fail");
        Investor storage investor = investors[msg.sender];
        require(investor.amountFunded > 0, "Not an investor");
        require(!investor.refunded, "Already refunded");

        investor.refunded = true;

        // Transfer tokens back to investor
        require(
            fundingToken.transfer(msg.sender, investor.amountFunded),
            "Token transfer failed"
        );

        emit Refunded(msg.sender, investor.amountFunded);
    }

    // Admin functions
    function closeFunding()
        external
        onlyEscrowAdmin
        inStatus(LoanStatus.OpenForFunding)
        updateStatus
    {
        status = LoanStatus.Funded;
        loanFundedDate = block.timestamp; // Record the date when funding is complete
        emit FundingClosed();
    }

    function stopFunding() external onlyEscrowAdmin nonReentrant {
        require(
            status == LoanStatus.OpenForFunding || status == LoanStatus.Funded,
            "Cannot stop funding at this stage"
        );
        status = LoanStatus.FundingFailed;
        emit FundingFailed();
        emit FundingStoppedByAdmin();
    }

    function changeInvestorAddress(
        address _oldAddress,
        address _newAddress
    ) external onlyEscrowAdmin {
        require(_oldAddress != _newAddress, "Addresses must be different");
        require(
            investors[_oldAddress].amountFunded > 0,
            "Old address is not an investor"
        );
        require(
            investors[_newAddress].amountFunded == 0,
            "New address is already an investor"
        );

        // Move investor data
        investors[_newAddress] = investors[_oldAddress];
        delete investors[_oldAddress];

        // Update investorList
        for (uint256 i = 0; i < investorList.length; i++) {
            if (investorList[i] == _oldAddress) {
                investorList[i] = _newAddress;
                break;
            }
        }

        emit InvestorAddressChanged(_oldAddress, _newAddress);
    }

    // Getter functions
    function getTotalDebt() public view returns (uint256) {
        // Simple Interest: Total Debt = Principal + (Principal * Rate * Time) / (10000 * 12)
        uint256 totalInterest = amountNeeded
            .mul(borrowerRate)
            .mul(loanTermMonths)
            .div(10000)
            .div(12);
        uint256 total = amountNeeded.add(totalInterest);
        return total;
    }

    function getOutstandingPrincipal() public view returns (uint256) {
        uint256 totalDebt = getTotalDebt();
        uint256 paymentsMade = totalPaymentsMade;
        uint256 amountPaid = totalDebt.mul(paymentsMade).div(loanTermMonths);
        if (totalRepaid >= totalDebt) {
            return 0;
        }
        uint256 outstanding = totalDebt.sub(amountPaid);
        return outstanding;
    }

    function getNextPaymentAmount() public view returns (uint256) {
        // Monthly Payment = Total Debt / Loan Term Months
        uint256 totalDebt = getTotalDebt();
        uint256 monthlyPayment = totalDebt.div(loanTermMonths);
        return monthlyPayment;
    }

    function getNextPaymentDate() public view returns (uint256) {
        if (status != LoanStatus.Active && status != LoanStatus.PreDefault) {
            return 0;
        }

        uint256 nextPaymentTimestamp = loanStartDate.add(
            totalPaymentsMade.mul(PAYMENT_INTERVAL)
        );
        return nextPaymentTimestamp;
    }

    function calculateDefaultPenalty() public view returns (uint256) {
        uint256 penaltyInterestRate = borrowerRate.mul(2); // Double the annual rate
        uint256 penalty = amountNeeded
            .mul(penaltyInterestRate)
            .mul(loanTermMonths.sub(totalPaymentsMade))
            .div(10000)
            .div(12);
        return penalty;
    }

    function calculateEarlyRepaymentPenalty() public view returns (uint256) {
        if (status != LoanStatus.Active && status != LoanStatus.PreDefault) {
            return 0;
        }

        uint256 loanEndDate = loanStartDate.add(
            loanTermMonths.mul(PAYMENT_INTERVAL)
        );
        if (block.timestamp > loanEndDate) {
            return 0;
        }

        uint256 remainingTime = loanEndDate.sub(block.timestamp);
        uint256 remainingDays = remainingTime.div(1 days);
        uint256 totalLoanDays = loanTermMonths.mul(30);

        // Penalty Rate = (Interest Rate / 2) * (remainingDays / totalLoanDays)
        uint256 penaltyRate = investorRate.div(2).mul(remainingDays).div(
            totalLoanDays
        );
        uint256 outstandingPrincipal = getOutstandingPrincipal();
        uint256 penalty = outstandingPrincipal.mul(penaltyRate).div(10000);
        return penalty;
    }

    function getEarlyRepaymentAmount() public view returns (uint256) {
        uint256 outstandingPrincipal = getOutstandingPrincipal();
        uint256 penalty = calculateEarlyRepaymentPenalty();
        return outstandingPrincipal.add(penalty);
    }

    function calculateInvestorOwed(
        address _investor
    ) public view returns (uint256) {
        if (status < LoanStatus.Active) {
            return 0;
        }

        Investor storage investor = investors[_investor];
        if (investor.amountFunded == 0) {
            return 0;
        }

        uint256 investorShare = investor.amountFunded.mul(1e18).div(
            totalFunded
        );
        uint256 totalRepaidToInvestors = totalRepaid; // Assuming all repayments go to investors

        uint256 amountOwed = totalRepaidToInvestors.mul(investorShare).div(
            1e18
        );

        uint256 amountWithdrawn = investor.amountWithdrawn;
        if (amountOwed <= amountWithdrawn) {
            return 0;
        } else {
            return amountOwed.sub(amountWithdrawn);
        }
    }

    function getInvestors() external view returns (address[] memory) {
        return investorList;
    }

    // Fallback function to reject ETH
    receive() external payable {
        revert("This contract does not accept ETH");
    }
}
