const hre = require("hardhat");

/**
 * V2 P (07/06/2026) : deploiement du RevenueLedger.
 *
 * Le RevenueLedger est un contrat singleton (deploye 1 seule fois par
 * environnement). Son adresse est ensuite stockee dans application.yaml
 * cote backend (variable BLOCKCHAIN_REVENUE_LEDGER_ADDRESS).
 *
 *   npx hardhat run scripts/deploy-revenue-ledger.js --network sepolia
 *
 * En mode dev local, le smoke test deploie + appelle enregistrerRevenu +
 * enregistrerDistribution pour verifier que les events sont bien emis.
 */
async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const network = hre.network.name;

  console.log("============================================================");
  console.log("Deploiement RevenueLedger");
  console.log("============================================================");
  console.log("Network  :", network);
  console.log("Deployer :", deployer.address);
  console.log("------------------------------------------------------------");

  const Factory = await hre.ethers.getContractFactory("RevenueLedger");
  const ledger = await Factory.deploy();
  await ledger.waitForDeployment();
  const address = await ledger.getAddress();

  console.log("OK - RevenueLedger deploye a", address);
  if (network === "sepolia") {
    console.log("Etherscan:", "https://sepolia.etherscan.io/address/" + address);
    console.log("");
    console.log(">>> A reporter dans le backend :");
    console.log("    BLOCKCHAIN_REVENUE_LEDGER_ADDRESS=" + address);
    return; // Pas de smoke test sur Sepolia (eviter de polluer)
  }
  console.log("------------------------------------------------------------");

  // Smoke test (hardhat in-memory uniquement)
  const fakeProp = "0x1234567890abcdef1234567890abcdef12345678";
  const fakeInv1 = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  const fakeInv2 = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  const hash     = "0x" + "ab".repeat(32);

  console.log("Test 1 : enregistrerRevenu(prop, Q2 2026, 5000 USD, ...)");
  let tx = await ledger.enregistrerRevenu(fakeProp, 20262, 5000, 1717804800, hash, 42);
  let receipt = await tx.wait();
  console.log("  -> tx mined gas =", receipt.gasUsed.toString());
  console.log("  nombreRevenus =", (await ledger.nombreRevenus(fakeProp)).toString());

  console.log("Test 2 : enregistrerDistribution unitaire (inv1, 1200 USD)");
  tx = await ledger.enregistrerDistribution(fakeProp, fakeInv1, 42, 1200);
  receipt = await tx.wait();
  console.log("  -> tx mined gas =", receipt.gasUsed.toString());
  console.log("  dividendesPercus inv1 =",
              (await ledger.dividendesPercus(fakeProp, fakeInv1)).toString());

  console.log("Test 3 : enregistrerDistributionBatch (inv1=800, inv2=3000)");
  tx = await ledger.enregistrerDistributionBatch(
    fakeProp, 42, [fakeInv1, fakeInv2], [800, 3000]
  );
  receipt = await tx.wait();
  console.log("  -> tx mined gas =", receipt.gasUsed.toString());
  console.log("  dividendesPercus inv1 cumule =",
              (await ledger.dividendesPercus(fakeProp, fakeInv1)).toString());
  console.log("  dividendesPercus inv2 cumule =",
              (await ledger.dividendesPercus(fakeProp, fakeInv2)).toString());
  console.log("  totalDistribueParPropriete =",
              (await ledger.totalDistribueParPropriete(fakeProp)).toString());

  console.log("------------------------------------------------------------");
  console.log("Smoke test OK");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
