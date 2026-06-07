const hre = require("hardhat");

/**
 * V2 T (07/06/2026) : deploiement du KycRegistry (singleton).
 *
 *   npx hardhat run scripts/deploy-kyc-registry.js --network sepolia
 *
 * Apres deploiement, l'adresse doit etre reportee dans le .env backend :
 *   BLOCKCHAIN_KYC_REGISTRY_ADDRESS=0x...
 *
 * Le smoke test in-memory (network=hardhat) valide enregistrement +
 * verification + revocation.
 */
async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const network = hre.network.name;

  console.log("============================================================");
  console.log("Deploiement KycRegistry");
  console.log("============================================================");
  console.log("Network  :", network);
  console.log("Deployer :", deployer.address);
  console.log("------------------------------------------------------------");

  const Factory = await hre.ethers.getContractFactory("KycRegistry");
  const kyc = await Factory.deploy();
  await kyc.waitForDeployment();
  const address = await kyc.getAddress();

  console.log("OK - KycRegistry deploye a", address);
  if (network === "sepolia") {
    console.log("Etherscan:", "https://sepolia.etherscan.io/address/" + address);
    console.log("");
    console.log(">>> A reporter dans le .env backend :");
    console.log("    BLOCKCHAIN_KYC_REGISTRY_ADDRESS=" + address);
    return;
  }
  console.log("------------------------------------------------------------");

  // Smoke test (hardhat in-memory uniquement)
  const fakeWallet = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  const fakeHash   = "0x" + "ab".repeat(32);
  const validation = 1717804800; // 2024-06-08
  const expire     = 1749340800; // 2025-06-08 (1 an plus tard)

  console.log("Test 1 : enregistrerKyc");
  let tx = await kyc.enregistrerKyc(fakeWallet, fakeHash, validation, expire);
  let receipt = await tx.wait();
  console.log("  -> tx mined gas =", receipt.gasUsed.toString());

  console.log("Test 2 : kycValide(wallet) — attendu false car expire est dans le passe");
  const valide = await kyc.kycValide(fakeWallet);
  console.log("  ->", valide ? "true (BUG)" : "false (OK)");

  console.log("Test 3 : enregistrerKyc avec expire dans le futur");
  const futureExpire = Math.floor(Date.now() / 1000) + 365 * 24 * 3600;
  tx = await kyc.enregistrerKyc(fakeWallet, fakeHash, Math.floor(Date.now() / 1000), futureExpire);
  await tx.wait();
  const valide2 = await kyc.kycValide(fakeWallet);
  console.log("  -> kycValide =", valide2);

  console.log("Test 4 : verifierHash avec hash correct");
  const verif = await kyc.verifierHash(fakeWallet, fakeHash);
  console.log("  -> verifierHash =", verif);

  console.log("Test 5 : verifierHash avec hash incorrect");
  const bad = await kyc.verifierHash(fakeWallet, "0x" + "cd".repeat(32));
  console.log("  -> verifierHash =", bad);

  console.log("Test 6 : revoquerKyc");
  tx = await kyc.revoquerKyc(fakeWallet, "test smoke");
  receipt = await tx.wait();
  console.log("  -> tx mined gas =", receipt.gasUsed.toString());
  console.log("  kycValide apres revocation =", await kyc.kycValide(fakeWallet));

  console.log("------------------------------------------------------------");
  console.log("Smoke test OK");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
