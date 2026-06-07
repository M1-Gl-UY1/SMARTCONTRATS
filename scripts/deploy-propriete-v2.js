const hre = require("hardhat");

/**
 * V2 O (07/06/2026) : deploiement smoke test du ProprieteTokenV2.
 *
 * Le contrat V2 ajoute par rapport a V1 :
 *   - prix mutable (sync via syncPrix(...))
 *   - devise (string)
 *   - statut (PUBLIEE / SUSPENDUE / RETIREE)
 *   - events PrixCourantChange, BonusChange, StatutChange
 *
 * Exemple :
 *   PROP_NOM="Villa Paje Test" PROP_ID=999 PROP_PARTS=1000 PROP_PRIX=1000 PROP_DEVISE=USD \
 *   npx hardhat run scripts/deploy-propriete-v2.js --network sepolia
 *
 * Apres deploiement, le script teste 2 appels live :
 *   1. syncPrix(...)    -> recalcul prix + bonus
 *   2. setStatut(SUSPENDUE) puis setStatut(PUBLIEE)
 */
async function main() {
  const nom     = process.env.PROP_NOM    || "Smoke Test V2";
  const idProp  = process.env.PROP_ID     || "999";
  const parts   = process.env.PROP_PARTS  || "1000";
  // Prix initial en USD entier (cf modele backend : pas de centimes on-chain).
  const prix    = process.env.PROP_PRIX   || "1000";
  const devise  = process.env.PROP_DEVISE || "USD";

  const [deployer] = await hre.ethers.getSigners();
  const network = hre.network.name;

  console.log("============================================================");
  console.log("Deploiement ProprieteTokenV2 (smoke test)");
  console.log("============================================================");
  console.log("Network  :", network);
  console.log("Deployer :", deployer.address);
  console.log("Params   :", { nom, idProp, parts, prix, devise });
  console.log("------------------------------------------------------------");

  const Factory = await hre.ethers.getContractFactory("ProprieteTokenV2");
  const contract = await Factory.deploy(nom, idProp, parts, prix, devise);
  await contract.waitForDeployment();
  const address = await contract.getAddress();

  console.log("OK - ProprieteTokenV2 deploye a", address);
  if (network === "sepolia") {
    console.log("Etherscan:", "https://sepolia.etherscan.io/address/" + address);
  }
  console.log("------------------------------------------------------------");

  // Lectures initiales pour verifier que le constructeur a bien tout pose.
  const prixInitial = await contract.prixInitialPart();
  const prixCourant = await contract.prixCourantPart();
  const bonusRenta  = await contract.bonusRentabiliteBps();
  const bonusDem    = await contract.bonusDemandeBps();
  const statut      = await contract.statut();
  const dev         = await contract.devise();
  console.log("Etat initial :");
  console.log("  prixInitial      =", prixInitial.toString());
  console.log("  prixCourant      =", prixCourant.toString());
  console.log("  bonusRentaBps    =", bonusRenta.toString());
  console.log("  bonusDemandeBps  =", bonusDem.toString());
  console.log("  statut           =", statut.toString(), "(0=PUBLIEE, 1=SUSPENDUE, 2=RETIREE)");
  console.log("  devise           =", dev);
  console.log("------------------------------------------------------------");

  // Test 1 : syncPrix(nouveauPrix=1112, renta=+325bps, demande=+800bps, raison=1, sourceId=42)
  // Correspond a l'exemple chiffre de la doc :
  //   prix = 1000 * (1 + 0.0325 + 0.08) = 1112.50 -> arrondi 1112
  console.log("Test 1 : syncPrix(1112, +325bps, +800bps, raison=REVENU_VALIDE, sourceId=42)");
  let tx = await contract.syncPrix(1112, 325, 800, 1, 42);
  let receipt = await tx.wait();
  console.log("  -> tx mined dans le bloc", receipt.blockNumber, "gas =", receipt.gasUsed.toString());
  const prixApres = await contract.prixCourantPart();
  console.log("  prixCourant apres syncPrix =", prixApres.toString());

  // Test 2 : setStatut SUSPENDUE puis PUBLIEE
  console.log("Test 2 : setStatut(SUSPENDUE)");
  tx = await contract.setStatut(1);
  receipt = await tx.wait();
  console.log("  -> tx mined gas =", receipt.gasUsed.toString());
  console.log("  statut =", (await contract.statut()).toString());

  console.log("Test 2b : setStatut(PUBLIEE)");
  tx = await contract.setStatut(0);
  await tx.wait();
  console.log("  statut =", (await contract.statut()).toString());

  console.log("------------------------------------------------------------");
  console.log("Smoke test OK");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
