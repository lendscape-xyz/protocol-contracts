// scripts/deploy.js
const hre = require("hardhat");
require("dotenv").config();

// Функция для ожидания заданного количества секунд
function sleep(seconds) {
  return new Promise((resolve) => setTimeout(resolve, seconds * 1000));
}

async function main() {
  // Компиляция контрактов
  await hre.run('compile');

  // Получение фабрики контрактов
  const LoanPool = await hre.ethers.getContractFactory("LoanPool");

  // Определение параметров конструктора

  // Struct Addresses
  const addresses = {
    borrower: "0x5A5e73abe907109Dd5Ba772784333220cecC6464", // Замените на реальный адрес заемщика
    escrowAdmin: "0x1E8070E40128f127FcbfEe745490f4149c6F0000", // Замените на реальный адрес администратора эскроу
    fundingToken: "0xc2132d05d31c914a87c6611c10748aeb04b58e8f", // USDT на Polygon
    protocolWallet: "0x1E8070E40128f127FcbfEe745490f4149c6F0000", // Замените на реальный адрес протокольного кошелька
    reserveFundAddress: "0x1E8070E40128f127FcbfEe745490f4149c6F0000", // Замените на реальный адрес резервного фонда
  };

  // Определение ставок в процентах
  const borrowerRatePercent = 35; // 35%
  const platformRatePercent = 7;  // 7%

  // Конвертация ставок в базисные пункты (1% = 100 базисных пунктов)
  const borrowerRate = borrowerRatePercent * 100; // 3500 базисных пунктов
  const platformRate = platformRatePercent * 100; // 700 базисных пунктов

  // Struct LoanParameters
  const loanParameters = {
    amountNeeded: hre.ethers.utils.parseUnits("1", 6), // 1000 USDT
    borrowerRate: borrowerRate, // 3500 базисных пунктов (35%)
    platformRate: platformRate,  // 700 базисных пунктов (7%)
    loanTermMonths: 12, // 12 месяцев
    fundingDeadline: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60), // Крайний срок финансирования через 30 дней
    setupFee: hre.ethers.utils.parseUnits("0.05", 6), // 5 USDT сбор за настройку
  };

  // Struct ComplianceInfo
  const complianceInfo = {
    kycRequired: false, // Установите true, если требуется KYC
    registry: "0x1E8070E40128f127FcbfEe745490f4149c6F0000", // Замените на реальный адрес контракта реестра
    compliance: hre.ethers.utils.formatBytes32String("COMPLIANCE_ID"), // Замените на реальный идентификатор соответствия
  };

  // Struct MetadataURIs
  const metadataURIs = {
    poolMetadataURI: "ipfs://your_pool_metadata_uri_here", // Замените на реальный URI
    loanMetadataURI: "ipfs://your_loan_metadata_uri_here", // Замените на реальный URI
  };

  // Деплой контракта
  const loanPool = await LoanPool.deploy(
    addresses,
    loanParameters,
    complianceInfo,
    metadataURIs
  );

  await loanPool.deployed();

  console.log("LoanPool деплоен по адресу:", loanPool.address);

  // Ожидание 15 секунд перед верификацией
  console.log("Ожидание 15 секунд перед верификацией контракта...");
  await sleep(600); // Ожидание 15 секунд

  // Верификация контракта
  try {
    await hre.run("verify:verify", {
      address: loanPool.address,
      constructorArguments: [
        addresses,
        loanParameters,
        complianceInfo,
        metadataURIs,
      ],
    });
    console.log("Контракт успешно верифицирован на PolygonScan.");
  } catch (error) {
    console.error("Ошибка верификации контракта:", error);
    // Дополнительно можно добавить повторную попытку или другие действия
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Ошибка деплоя контракта:", error);
    process.exit(1);
  });
