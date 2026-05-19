const hre = require("hardhat");

// Parametres a passer via variables d'env pour eviter de hardcoder
// Exemple :
//   PROP_NOM="Villa Paje" PROP_ID=42 PROP_PARTS=1000 PROP_PRIX_WEI=10000000000000000 \
//   npx hardhat run scripts/deploy-propriete.js --network sepolia
async function main() {
  const nom    = process.env.PROP_NOM    || "Test Propriete FURSA";
  const idProp = process.env.PROP_ID     || "1";
  const parts  = process.env.PROP_PARTS  || "1000";
  const prixWei = process.env.PROP_PRIX_WEI || "10000000000000000"; // 0.01 ETH par defaut

  const [deployer] = await hre.ethers.getSigners();
  const network = hre.network.name;

  console.log("============================================================");
  console.log("Deploiement ProprieteToken");
  console.log("============================================================");
  console.log("Network  :", network);
  console.log("Deployer :", deployer.address);
  console.log("Params   :", { nom, idProp, parts, prixWei });
  console.log("------------------------------------------------------------");

  const Factory = await hre.ethers.getContractFactory("ProprieteToken");
  const contract = await Factory.deploy(nom, idProp, parts, prixWei);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("OK - ProprieteToken (" + nom + ") deploye a", address);
  if (network === "sepolia") {
    console.log("Etherscan:", "https://sepolia.etherscan.io/address/" + address);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
