# Lendscape LoanPool Smart Contracts

The Lendscape `LoanPool` smart contract is a decentralized lending platform built on Ethereum-compatible blockchains, designed to facilitate loan agreements between borrowers and investors. This contract allows borrowers to request loans with specific terms, and investors to fund these loans, earning interest over time.

## Table of Contents

- [Features](#features)
- [Contract Structure](#contract-structure)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Usage](#usage)
  - [Investor Functions](#investor-functions)
  - [Borrower Functions](#borrower-functions)
  - [Admin Functions](#admin-functions)
  - [Getter Functions](#getter-functions)
- [Events](#events)
- [Security Considerations](#security-considerations)
- [License](#license)

## Features

- **Loan Lifecycle Management**: Handles the entire lifecycle of a loan, including funding, activation, repayment, and default scenarios.
- **Investor Participation**: Allows multiple investors to fund a loan, tracking their individual contributions and repayments.
- **Compliance Integration**: Optional KYC and compliance checks via a registry contract.
- **Flexible Terms**: Supports customizable loan parameters such as interest rates, loan terms, funding deadlines, and fees.
- **Safety Mechanisms**: Implements reentrancy guards and SafeMath operations to enhance security.

## Contract Structure

The contract consists of several key components:

- **Enums**:
  - `LoanStatus`: Represents the current status of the loan (e.g., OpenForFunding, Funded, Active, Defaulted, Closed).

- **Structs**:
  - `LoanParameters`: Holds the financial parameters of the loan.
  - `Addresses`: Contains important addresses involved in the loan (e.g., borrower, escrow admin, funding token).
  - `ComplianceInfo`: Holds compliance-related information if KYC is required.
  - `MetadataURIs`: Stores URIs for metadata about the pool and the loan.
  - `Investor`: Tracks each investor's contribution and repayments.

- **Variables**:
  - Loan terms, funding details, repayment tracking, compliance settings, and mappings for investors.

- **Modifiers**:
  - `onlyBorrower`: Restricts functions to be called only by the borrower.
  - `onlyEscrowAdmin`: Restricts functions to be called only by the escrow admin.
  - `inStatus`: Ensures that a function can only be called when the loan is in a specific status.
  - `updateStatus`: Automatically updates the loan status before executing a function.

- **Events**:
  - Emitted throughout the loan lifecycle to provide transparency and traceability (e.g., `Funded`, `LoanActivated`, `RepaymentMade`).

## Prerequisites

- **Node.js** and **npm** installed.
- **Hardhat**: Ethereum development environment.
- **Ethereum-compatible wallet** with testnet or mainnet funds.
- **Polygon RPC URL** and **Private Key** set in environment variables.
- **Etherscan API Key** (if you plan to verify the contract on a block explorer).

## Deployment

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/loanpool-contract.git
cd loanpool-contract
```

### 2. Install Dependencies

```bash
npm install
```

### 3. Set Up Environment Variables

Create a `.env` file in the root directory and add the following:

```bash
PRIVATE_KEY=your_private_key
POLYGON_RPC_URL=https://polygon-rpc.com
POLYGONSCAN_API_KEY=your_polygonscan_api_key
```

### 4. Compile the Contracts

```bash
npx hardhat compile
```

### 5. Deploy the Contract

Update the `scripts/deploy.js` file with appropriate constructor arguments. Then run:

```bash
npx hardhat run scripts/deploy.js --network polygon
```

### 6. Verify the Contract (Optional)

If you have provided a block explorer API key:

```bash
npx hardhat verify --network polygon <contract_address> <constructor_arguments>
```

## Usage

### Investor Functions

- **Fund a Loan**: Investors can fund the loan during the `OpenForFunding` status.

  ```javascript
  await loanPool.connect(investor).fund(amount);
  ```

- **Claim Repayments**: Investors can claim their share of repayments when available.

  ```javascript
  await loanPool.connect(investor).claim();
  ```

- **Refund**: If funding fails, investors can refund their contributions.

  ```javascript
  await loanPool.connect(investor).refund();
  ```

### Borrower Functions

- **Activate Loan**: Borrower activates the loan after funding is successful.

  ```javascript
  await loanPool.connect(borrower).activateLoan();
  ```

- **Repay**: Make scheduled repayments.

  ```javascript
  await loanPool.connect(borrower).repay();
  ```

- **Early Repay**: Optionally repay the loan early with possible penalties.

  ```javascript
  await loanPool.connect(borrower).earlyRepay();
  ```

### Admin Functions

- **Close Funding**: Escrow admin can manually close funding.

  ```javascript
  await loanPool.connect(escrowAdmin).closeFunding();
  ```

- **Stop Funding**: Escrow admin can stop funding in exceptional cases.

  ```javascript
  await loanPool.connect(escrowAdmin).stopFunding();
  ```

- **Change Investor Address**: Update an investor's address in case of changes.

  ```javascript
  await loanPool.connect(escrowAdmin).changeInvestorAddress(oldAddress, newAddress);
  ```

### Getter Functions

- **Get Total Debt**:

  ```javascript
  const totalDebt = await loanPool.getTotalDebt();
  ```

- **Get Outstanding Principal**:

  ```javascript
  const outstandingPrincipal = await loanPool.getOutstandingPrincipal();
  ```

- **Get Next Payment Amount**:

  ```javascript
  const nextPaymentAmount = await loanPool.getNextPaymentAmount();
  ```

- **Get Next Payment Date**:

  ```javascript
  const nextPaymentDate = await loanPool.getNextPaymentDate();
  ```

- **Calculate Investor Owed**:

  ```javascript
  const amountOwed = await loanPool.calculateInvestorOwed(investorAddress);
  ```

## Events

The contract emits several events to track the state changes:

- `Funded(address investor, uint256 amount)`
- `FundingClosed()`
- `FundingFailed()`
- `LoanActivated()`
- `RepaymentMade(uint256 amount)`
- `PaymentMissed()`
- `LoanDefaulted()`
- `Claimed(address investor, uint256 amount)`
- `Refunded(address investor, uint256 amount)`
- `LoanClosed()`
- `EarlyRepaid(uint256 amount, uint256 penalty)`
- `InvestorAddressChanged(address oldAddress, address newAddress)`

Listen to these events in your application to monitor the loan status.

## Security Considerations

- **Reentrancy Guard**: The contract uses OpenZeppelin's `ReentrancyGuard` to prevent reentrancy attacks.
- **SafeMath**: Utilizes `SafeMath` for safe arithmetic operations.
- **Access Control**: Functions are protected with modifiers to restrict access to authorized parties.
- **Compliance Checks**: Optional KYC and compliance checks can be enforced via a registry.

## License

This project is licensed under the MIT License.

---

**Note**: Replace placeholder values like `your_private_key`, `your_polygonscan_api_key`, `yourusername`, and URIs with actual data relevant to your deployment.
