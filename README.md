# FURSA Smart Contracts

Smart contracts Solidity de la plateforme FURSA Community (investissement immobilier
fractionne). Deploye sur Sepolia (testnet Ethereum) en phase V1.5, cible Polygon en V2.

## Contrats

| Contrat               | Role |
|-----------------------|------|
| `RevenueDistribution.sol` | Registre on-chain des investisseurs + distribution des dividendes. Owner = backend custodial. |
| `ProprieteToken.sol`  | Token ERC-20 par bien immobilier (1 contrat = 1 propriete). Permet d'acheter des parts contre ETH. |

## Stack

- **Solidity** `0.8.20`
- **Hardhat** `^2.22` (build + deploy + test)
- **OpenZeppelin Contracts** `^5.0` (ERC-20, Ownable)
- **Reseau dev** : Hardhat local (chainId 31337)
- **Reseau test** : Sepolia testnet (chainId 11155111)

## Setup local

```bash
# Pre-requis : Node.js >= 18
npm install
npx hardhat compile
```

## Deploiement Sepolia

### 1. Variables d'environnement

Copier `.env.example` en `.env` (jamais committe, deja dans `.gitignore`) et remplir :

```env
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/<TON_API_KEY_ALCHEMY>
SEPOLIA_DEPLOYER_PRIVATE_KEY=0x<64 caracteres hex>
ETHERSCAN_API_KEY=<optionnel - pour publier le source du contrat>
```

- L'**Alchemy API key** : https://dashboard.alchemy.com -> New App -> Network Sepolia
- La **cle privee** : MetaMask -> compte dedie -> Details -> Afficher la cle privee
  - JAMAIS la partager (chat, screenshot, repo). Le wallet est use only pour deploy + signature.
- L'**ETH Sepolia** : https://cloud.google.com/application/web3/faucet/ethereum/sepolia (0.05 ETH/24h)

### 2. Deployer le contrat principal

```bash
npx hardhat run scripts/deploy.js --network sepolia
```

Sortie attendue :

```
============================================================
OK - RevenueDistribution deploye
============================================================
Adresse  : 0x5F24D4e615e60C2cfA959CfDFcf82c7937A969b9
Tx       : 0xbaace75bd136a502...
Etherscan: https://sepolia.etherscan.io/address/0x5F24...969b9
>>> Mettre cette adresse dans le .env du backend :
    BLOCKCHAIN_CONTRACT_ADDRESS=0x5F24D4e615e60C2cfA959CfDFcf82c7937A969b9
```

### 3. (Optionnel) Verifier le source sur Etherscan

```bash
npx hardhat verify --network sepolia 0x5F24D4e615e60C2cfA959CfDFcf82c7937A969b9
```

### 4. Deployer un `ProprieteToken` (une fois par bien immobilier)

```bash
PROP_NOM="Fumba Town Villa" \
PROP_ID=1 \
PROP_PARTS=1000 \
PROP_PRIX_WEI=10000000000000000 \
npx hardhat run scripts/deploy-propriete.js --network sepolia
```

(`10000000000000000` wei = 0.01 ETH par part)

## Branchement avec le backend

Le backend Spring Boot consomme ces contrats via Web3j. Les vars d'env a configurer :

```env
BLOCKCHAIN_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/<KEY>
BLOCKCHAIN_CONTRACT_ADDRESS=0x5F24D4e615e60C2cfA959CfDFcf82c7937A969b9   # RevenueDistribution
BLOCKCHAIN_OWNER_PRIVATE_KEY=0x<cle privee owner>
BLOCKCHAIN_CHAIN_ID=11155111
BLOCKCHAIN_GAS_PRICE=2000000000
BLOCKCHAIN_GAS_LIMIT=300000
```

En prod, ces vars viennent des **GitHub Secrets** du repo `FURSA-BACKEND` et sont
injectees automatiquement dans le `.env` du VPS par le workflow `.github/workflows/deploy.yml`.

## Si tu modifies les contrats

1. Recompile : `npx hardhat compile`
2. Re-genere le wrapper Java pour le backend :
   ```bash
   web3j generate solidity \
     -a artifacts/contracts/RevenueDistribution.sol/RevenueDistribution.json \
     -o ../FURSA-BACKEND/src/main/java \
     -p com.fursa.fursa_backend.blockchain.wrapper
   ```
3. Redeploie sur Sepolia (le nouveau contrat aura une nouvelle adresse)
4. Mets a jour le secret GitHub `BLOCKCHAIN_CONTRACT_ADDRESS` sur le repo backend
5. Re-deploie le backend (push sur `main`)

> Sur Sepolia/testnet, chaque redeploy coute du gas testnet (gratuit via faucet).
> Sur Polygon mainnet, ce sera ~0.005 EUR. Sur Ethereum mainnet ~50-150 EUR.
> Les smart contracts sont immuables : un redeploy = un nouveau contrat, l'ancien
> reste pour toujours sur la chain.

## Migration future vers Polygon

Vu en mémoire du projet : la cible prod est Polygon (frais bas, EVM-compatible).
Le code Solidity et les scripts Hardhat marcheront tels quels — il suffit d'ajouter
un network `polygon` ou `amoy` (testnet Polygon) dans `hardhat.config.js`.

## Reseaux configures

| Network    | chainId   | RPC                                              |
|------------|-----------|--------------------------------------------------|
| `hardhat`  | 31337     | in-memory                                        |
| `localhost`| 31337     | http://127.0.0.1:8545                            |
| `sepolia`  | 11155111  | `$SEPOLIA_RPC_URL` (Alchemy)                     |

## Scripts npm

| Script                       | Effet |
|------------------------------|-------|
| `npm run compile`            | `hardhat compile` |
| `npm run test`               | `hardhat test` |
| `npm run node`               | demarre un node Hardhat local |
| `npm run deploy:local`       | deploie sur le node Hardhat local |
| `npm run deploy:sepolia`     | deploie `RevenueDistribution` sur Sepolia |
| `npm run deploy:propriete:sepolia` | deploie un `ProprieteToken` (params via env) |
| `npm run verify:sepolia`     | publie le source sur Sepolia Etherscan |
