// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title KycRegistry
 * @notice V2 T (07/06/2026) : registre on-chain RGPD-safe des KYC valides FURSA.
 *
 *   PRINCIPE : aucune donnee perso n'est jamais inscrite on-chain.
 *   Seuls sont stockes :
 *     - le hash keccak256 du dossier KYC (concatene avec un sel secret backend)
 *     - le statut (VALIDE / EXPIRE / REVOQUE)
 *     - les dates de validation et d'expiration
 *
 *   Le hash est non-reversible. Sans connaitre les donnees perso ET le sel
 *   backend, personne ne peut deviner l'identite d'un titulaire.
 *
 *   En cas de droit a l'oubli (RGPD) : on supprime les donnees perso en BDD et
 *   on appelle revoquerKyc(adresse). Le hash reste sur la chain (immuable) mais
 *   devient inverifiable (impossible de regenerer pour comparer).
 *
 *   Cas d'usage typiques :
 *     - prouver a un regulateur qu'a la date X, telle adresse avait un KYC valide
 *     - permettre a un smart contract DeFi de gater une operation sur kycValide(addr)
 *     - audit independant : n'importe qui peut lire kycValide(addr) sans backend
 */
contract KycRegistry is Ownable {

    enum Statut { INEXISTANT, VALIDE, EXPIRE, REVOQUE }

    struct KycRecord {
        bytes32 hashKyc;          // keccak256(prenom + nom + dateNaissance + numPiece + selSecret)
        Statut  statut;
        uint64  dateValidation;   // timestamp UNIX
        uint64  expireLe;         // timestamp UNIX (typiquement +12 mois)
    }

    /** Etat KYC indexe par adresse de wallet de l'investisseur. */
    mapping(address => KycRecord) public records;

    // ── Events ─────────────────────────────────────────────────────────────

    event KycEnregistre(
        address indexed wallet,
        bytes32 hashKyc,
        uint64  dateValidation,
        uint64  expireLe
    );

    event KycRevoque(
        address indexed wallet,
        uint64  dateRevocation,
        string  motif
    );

    event KycExpire(
        address indexed wallet,
        uint64  dateExpiration
    );

    constructor() Ownable(msg.sender) {}

    // ── Ecriture (onlyOwner = backend FURSA custodial) ─────────────────────

    /**
     * Enregistre un KYC valide. Si une entree existe deja, elle est remplacee
     * (cas typique : re-soumission apres expiration ou revocation).
     */
    function enregistrerKyc(
        address _wallet,
        bytes32 _hashKyc,
        uint64  _dateValidation,
        uint64  _expireLe
    ) external onlyOwner {
        require(_wallet != address(0),       "wallet = 0");
        require(_hashKyc != bytes32(0),       "hash = 0");
        require(_expireLe > _dateValidation,  "expire <= validation");

        records[_wallet] = KycRecord({
            hashKyc:        _hashKyc,
            statut:         Statut.VALIDE,
            dateValidation: _dateValidation,
            expireLe:       _expireLe
        });

        emit KycEnregistre(_wallet, _hashKyc, _dateValidation, _expireLe);
    }

    /**
     * Revoque un KYC. Garde le hash on-chain (audit historique) mais marque
     * le statut comme REVOQUE pour que kycValide(...) retourne false.
     */
    function revoquerKyc(address _wallet, string calldata _motif) external onlyOwner {
        require(_wallet != address(0), "wallet = 0");
        require(records[_wallet].statut == Statut.VALIDE
             || records[_wallet].statut == Statut.EXPIRE, "non revocable");

        records[_wallet].statut = Statut.REVOQUE;
        emit KycRevoque(_wallet, uint64(block.timestamp), _motif);
    }

    /**
     * Marque un KYC comme EXPIRE. Peut etre appele par owner (cron backend)
     * ou par n'importe qui si la date d'expiration est passee (anti-stagnation).
     */
    function marquerExpire(address _wallet) external {
        require(_wallet != address(0), "wallet = 0");
        KycRecord storage r = records[_wallet];
        require(r.statut == Statut.VALIDE,            "deja non-valide");
        require(block.timestamp >= r.expireLe,        "pas encore expire");
        r.statut = Statut.EXPIRE;
        emit KycExpire(_wallet, uint64(block.timestamp));
    }

    // ── Lectures (gratuit, n'importe qui) ─────────────────────────────────

    /** Retourne true si l'adresse a un KYC VALIDE et non expire (lecture par smart contract DeFi). */
    function kycValide(address _wallet) external view returns (bool) {
        KycRecord storage r = records[_wallet];
        if (r.statut != Statut.VALIDE) return false;
        return block.timestamp < r.expireLe;
    }

    /** Retourne tout le record (hash + statut + dates). */
    function getRecord(address _wallet) external view returns (KycRecord memory) {
        return records[_wallet];
    }

    /**
     * Verifie qu'un hash recompose off-chain correspond a celui on-chain.
     * Utilise par les regulateurs : on leur fournit les donnees perso, ils
     * recalculent le hash avec le sel public (ou un sel transmis sous accord
     * de confidentialite) et appellent cette fonction.
     */
    function verifierHash(address _wallet, bytes32 _hashAVerifier)
        external
        view
        returns (bool)
    {
        return records[_wallet].hashKyc == _hashAVerifier
            && records[_wallet].statut == Statut.VALIDE;
    }
}
