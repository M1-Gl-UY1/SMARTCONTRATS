// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ProprieteTokenV2
 * @notice V2 (Phase O — 07/06/2026) : extension du ProprieteToken initial.
 *
 *   Nouveautes par rapport a V1 :
 *   - Prix par part MUTABLE (sync regulier depuis BDD apres recalcul dynamique)
 *   - Bonus rentabilite + bonus demande on-chain (audit public de la formule)
 *   - Devise (string) immutable, ex: "USD"
 *   - Statut public (PUBLIEE / SUSPENDUE / RETIREE) mutable par l'owner
 *   - Events PrixCourantChange, BonusChange, StatutChange (traçabilite totale)
 *
 *   Tous les bonus sont exprimes en base 10000 (bps + 2 decimales) :
 *     +250  = +2.5%
 *     -100  = -1.0%
 *     +4000 = +40% (cap rentabilite)
 *     +3000 = +30% (cap demande)
 */
contract ProprieteTokenV2 is ERC20, Ownable {

    // ── Donnees immuables (gravees a la creation) ──────────────────────────

    uint256 public immutable idProprieteBackend;
    uint256 public immutable nombreTotalParts;
    /** Prix INITIAL a la creation (snapshot, sert de reference pour bornes). */
    uint256 public immutable prixInitialPart;
    /** Devise de reference (USD par defaut, decision Hugh 22/05/2026). */
    string  public devise;

    // ── Donnees mutables (synchronisees depuis FURSA backend) ──────────────

    /** Prix par part courant = prixInitial * (1 + bonusRenta/10000 + bonusDemande/10000). */
    uint256 public prixCourantPart;

    /** Bonus rentabilite cumule en bps signes (entre -4000 et +4000). */
    int256 public bonusRentabiliteBps;

    /** Bonus demande en bps non signes (entre 0 et +3000). */
    uint256 public bonusDemandeBps;

    /**
     * Statut public du bien sur la plateforme.
     *   0 = PUBLIEE   (achat possible, etat par defaut a la creation)
     *   1 = SUSPENDUE (achat temporairement bloque par admin)
     *   2 = RETIREE   (bien retire definitivement, plus achetable)
     */
    enum Statut { PUBLIEE, SUSPENDUE, RETIREE }
    Statut public statut;

    // ── Events ─────────────────────────────────────────────────────────────

    event PartAchetee(address indexed acheteur, uint256 montant);

    /** Emis a chaque sync prix depuis le backend. Raison codee enum-like. */
    event PrixCourantChange(
        uint256 ancienPrix,
        uint256 nouveauPrix,
        uint8   raison,        // 1=REVENU_VALIDE, 2=LISTE_ATTENTE, 3=CRON, 4=AJUSTEMENT_ADMIN
        uint256 sourceId       // id revenu / event source en BDD
    );

    /** Emis quand l'un des deux bonus change. */
    event BonusChange(
        int256  ancienBonusRenta,
        int256  nouveauBonusRenta,
        uint256 ancienBonusDemande,
        uint256 nouveauBonusDemande
    );

    event StatutChange(Statut ancien, Statut nouveau);

    // ── Constructeur ───────────────────────────────────────────────────────

    constructor(
        string  memory nomPropriete,
        uint256 _idBackend,
        uint256 _nombreParts,
        uint256 _prixInitial,
        string  memory _devise
    )
        ERC20(nomPropriete, "FURSA")
        Ownable(msg.sender)
    {
        require(_idBackend > 0,    "id backend invalide");
        require(_nombreParts > 0,  "parts > 0");
        require(_prixInitial > 0,  "prix > 0");
        require(bytes(_devise).length >= 3 && bytes(_devise).length <= 5, "devise invalide");

        idProprieteBackend = _idBackend;
        nombreTotalParts   = _nombreParts;
        prixInitialPart    = _prixInitial;
        devise             = _devise;

        // Etat de depart : prix courant = prix initial, bonus a 0, statut PUBLIEE.
        prixCourantPart     = _prixInitial;
        bonusRentabiliteBps = 0;
        bonusDemandeBps     = 0;
        statut              = Statut.PUBLIEE;

        _mint(address(this), _nombreParts);
    }

    /// Une part est une unite indivisible : 0 decimale.
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    // ── Sync depuis le backend (onlyOwner) ─────────────────────────────────

    /**
     * Met a jour le prix courant + les deux bonus en une seule tx.
     * Emis depuis PrixPartService apres recalcul BDD.
     *
     * @param _nouveauPrix    Nouveau prix courant en plus petite unite (ex: cents USD).
     * @param _bonusRentaBps  Nouveau bonus rentabilite cumule, bornes ±4000.
     * @param _bonusDemandeBps Nouveau bonus demande, borne 0..3000.
     * @param _raison         1=REVENU_VALIDE, 2=LISTE_ATTENTE, 3=CRON, 4=AJUSTEMENT_ADMIN
     * @param _sourceId       id de l'event en BDD (revenu_id, etc.)
     */
    function syncPrix(
        uint256 _nouveauPrix,
        int256  _bonusRentaBps,
        uint256 _bonusDemandeBps,
        uint8   _raison,
        uint256 _sourceId
    ) external onlyOwner {
        require(_nouveauPrix > 0, "prix > 0");
        require(_bonusRentaBps >= -4000 && _bonusRentaBps <= 4000, "renta hors cap");
        require(_bonusDemandeBps <= 3000, "demande hors cap");
        require(_raison >= 1 && _raison <= 4, "raison invalide");

        // Plancher / plafond : 50% / 200% du prix initial (cf PrixPartService.java)
        require(_nouveauPrix >= prixInitialPart / 2,     "sous plancher");
        require(_nouveauPrix <= prixInitialPart * 2,     "sur plafond");

        uint256 ancienPrix = prixCourantPart;
        int256  ancienBonusRenta = bonusRentabiliteBps;
        uint256 ancienBonusDemande = bonusDemandeBps;

        prixCourantPart     = _nouveauPrix;
        bonusRentabiliteBps = _bonusRentaBps;
        bonusDemandeBps     = _bonusDemandeBps;

        emit PrixCourantChange(ancienPrix, _nouveauPrix, _raison, _sourceId);
        emit BonusChange(ancienBonusRenta, _bonusRentaBps, ancienBonusDemande, _bonusDemandeBps);
    }

    /** Change le statut public du bien. */
    function setStatut(Statut _nouveau) external onlyOwner {
        Statut ancien = statut;
        statut = _nouveau;
        emit StatutChange(ancien, _nouveau);
    }

    // ── Achat de parts (custodial wallet uniquement, onlyOwner) ────────────

    /**
     * @notice En mode custodial (architecture FURSA actuelle), l'achat est
     * orchestre par le backend qui paye le gas. La methode reste payable
     * pour compat avec V1 mais elle exige que le statut soit PUBLIEE.
     */
    function acheterParts(uint256 nombreParts) external payable {
        require(statut == Statut.PUBLIEE, "bien non publie");
        require(nombreParts > 0, "Quantite invalide");
        require(msg.value == nombreParts * prixCourantPart, "Montant incorrect");
        require(balanceOf(address(this)) >= nombreParts, "Parts insuffisantes");
        _transfer(address(this), msg.sender, nombreParts);
        emit PartAchetee(msg.sender, nombreParts);
    }

    function partsDisponibles() external view returns (uint256) {
        return balanceOf(address(this));
    }
}
