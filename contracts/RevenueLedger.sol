// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RevenueLedger
 * @notice V2 P (07/06/2026) : registre on-chain singleton des revenus
 *   trimestriels valides et des distributions de dividendes pour toutes les
 *   proprietes FURSA.
 *
 *   Ce contrat n'est PAS une source de verite metier (la BDD reste autoritative).
 *   C'est un journal d'audit public, immuable et auto-portant :
 *     - n'importe qui peut verifier qu'on n'a pas trafique l'historique
 *     - chaque revenu porte un hash du justificatif (PDF), permettant de prouver
 *       que le document existait au moment de la validation
 *     - chaque distribution est tracee par investisseur (adresse + montant)
 *
 *   Owner = wallet master FURSA. Les setters sont onlyOwner car la plateforme
 *   reste custodial (FURSA paie le gas, signe pour les utilisateurs).
 */
contract RevenueLedger is Ownable {

    /**
     * Un revenu trimestriel valide pour une propriete donnee.
     *
     * @param proprieteToken adresse du contrat ProprieteTokenV2 concerne
     * @param trimestre      format YYYYQ : ex 20262 = Q2 2026, 20264 = Q4 2026
     * @param montantUsd     montant net en USD entiers
     * @param dateValidation timestamp unix de la validation admin
     * @param hashJustificatif keccak256 du PDF justificatif (preuve d'existence)
     * @param revenuIdBackend id en BDD FURSA (lien BDD <-> chain)
     */
    struct Revenu {
        address proprieteToken;
        uint32  trimestre;
        uint256 montantUsd;
        uint64  dateValidation;
        bytes32 hashJustificatif;
        uint256 revenuIdBackend;
    }

    /** Liste chronologique des revenus enregistres, indexee par adresse propriete. */
    mapping(address => Revenu[]) private revenusParPropriete;

    /**
     * Dividendes percus on-chain par chaque investisseur, par propriete.
     * mapping(propriete => mapping(investor => montantCumuleUsd)).
     */
    mapping(address => mapping(address => uint256)) public dividendesPercus;

    /** Suivi du total distribue par propriete (sanity check + KPI public). */
    mapping(address => uint256) public totalDistribueParPropriete;

    // ── Events ─────────────────────────────────────────────────────────────

    event RevenuEnregistre(
        address indexed proprieteToken,
        uint256 indexed revenuIdBackend,
        uint32  trimestre,
        uint256 montantUsd,
        bytes32 hashJustificatif,
        uint64  dateValidation
    );

    event DividendeDistribue(
        address indexed proprieteToken,
        address indexed investisseur,
        uint256 indexed revenuIdBackend,
        uint256 montantUsd
    );

    constructor() Ownable(msg.sender) {}

    // ── Ecriture (onlyOwner) ──────────────────────────────────────────────

    /**
     * Enregistre un revenu valide par l'admin. Idempotence faible :
     * un meme (propriete, trimestre) peut etre enregistre 2x si on relance — on
     * accepte le double pour eviter une perte de trace. Le caller (backend) doit
     * checker en BDD avant d'envoyer.
     */
    function enregistrerRevenu(
        address _proprieteToken,
        uint32  _trimestre,
        uint256 _montantUsd,
        uint64  _dateValidation,
        bytes32 _hashJustificatif,
        uint256 _revenuIdBackend
    ) external onlyOwner {
        require(_proprieteToken != address(0), "propriete = 0");
        require(_montantUsd > 0,                "montant = 0");
        require(_trimestre > 0,                 "trimestre invalide");

        Revenu memory r = Revenu({
            proprieteToken:   _proprieteToken,
            trimestre:        _trimestre,
            montantUsd:       _montantUsd,
            dateValidation:   _dateValidation,
            hashJustificatif: _hashJustificatif,
            revenuIdBackend:  _revenuIdBackend
        });
        revenusParPropriete[_proprieteToken].push(r);

        emit RevenuEnregistre(
            _proprieteToken, _revenuIdBackend, _trimestre,
            _montantUsd, _hashJustificatif, _dateValidation
        );
    }

    /**
     * Enregistre la distribution d'un dividende a un investisseur donne.
     * Plusieurs investisseurs peuvent etre logges en plusieurs appels (1 tx par
     * dividende) — le backend choisit le mode batch ou unitaire selon le cas.
     */
    function enregistrerDistribution(
        address _proprieteToken,
        address _investisseur,
        uint256 _revenuIdBackend,
        uint256 _montantUsd
    ) external onlyOwner {
        require(_proprieteToken != address(0), "propriete = 0");
        require(_investisseur != address(0),   "investisseur = 0");
        require(_montantUsd > 0,               "montant = 0");

        dividendesPercus[_proprieteToken][_investisseur] += _montantUsd;
        totalDistribueParPropriete[_proprieteToken] += _montantUsd;

        emit DividendeDistribue(
            _proprieteToken, _investisseur, _revenuIdBackend, _montantUsd
        );
    }

    /**
     * Variante batch : enregistre la distribution complete d'un revenu pour
     * une liste d'investisseurs en une seule tx. Plus economique en gas si
     * la liste est moyenne (<200 entrees).
     */
    function enregistrerDistributionBatch(
        address _proprieteToken,
        uint256 _revenuIdBackend,
        address[] calldata _investisseurs,
        uint256[] calldata _montantsUsd
    ) external onlyOwner {
        require(_proprieteToken != address(0),                "propriete = 0");
        require(_investisseurs.length == _montantsUsd.length, "tailles diff");
        require(_investisseurs.length > 0,                    "liste vide");

        uint256 totalBatch;
        for (uint256 i = 0; i < _investisseurs.length; ++i) {
            address inv = _investisseurs[i];
            uint256 m   = _montantsUsd[i];
            require(inv != address(0), "investisseur = 0");
            require(m > 0,             "montant = 0");
            dividendesPercus[_proprieteToken][inv] += m;
            totalBatch += m;
            emit DividendeDistribue(_proprieteToken, inv, _revenuIdBackend, m);
        }
        totalDistribueParPropriete[_proprieteToken] += totalBatch;
    }

    // ── Lectures (gratuit en read-only) ───────────────────────────────────

    function nombreRevenus(address _proprieteToken) external view returns (uint256) {
        return revenusParPropriete[_proprieteToken].length;
    }

    function revenuAt(address _proprieteToken, uint256 _index)
        external
        view
        returns (Revenu memory)
    {
        require(_index < revenusParPropriete[_proprieteToken].length, "index OOB");
        return revenusParPropriete[_proprieteToken][_index];
    }
}
