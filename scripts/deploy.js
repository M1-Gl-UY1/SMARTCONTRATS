const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const network = hre.network.name;
  const chainId = (await hre.ethers.provider.getNetwork()).chainId;
  const balance = await hre.ethers.provider.getBalance(deployer.address);

  console.log("============================================================");
  console.log("Deploiement RevenueDistribution");
  console.log("============================================================");
  console.log("Network  :", network, "(chainId", chainId.toString() + ")");
  console.log("Deployer :", deployer.address);
  console.log("Solde    :", hre.ethers.formatEther(balance), "ETH");
  console.log("------------------------------------------------------------");

  if (balance === 0n) {
    throw new Error("Solde 0 - faucet Sepolia obligatoire avant de deployer");
  }

  const Factory = await hre.ethers.getContractFactory("RevenueDistribution");
  const contract = await Factory.deploy();
  console.log("Tx envoyee, en attente de confirmation...");
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  const txHash = contract.deploymentTransaction().hash;

  console.log("============================================================");
  console.log("OK - RevenueDistribution deploye");
  console.log("============================================================");
  console.log("Adresse  :", address);
  console.log("Tx       :", txHash);
  if (network === "sepolia") {
    console.log("Etherscan:", "https://sepolia.etherscan.io/address/" + address);
  }
  console.log("");
  console.log(">>> Mettre cette adresse dans le .env du backend :");
  console.log("    BLOCKCHAIN_CONTRACT_ADDRESS=" + address);
  console.log("============================================================");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
