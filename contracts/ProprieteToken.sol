// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ProprieteToken is ERC20, Ownable {

    uint256 public immutable idProprieteBackend;
    uint256 public immutable nombreTotalParts;
    uint256 public immutable prixParPart;

    event PartAchetee(address indexed acheteur, uint256 montant);

    constructor(
        string memory nomPropriete,
        uint256 _idBackend,
        uint256 _nombreParts,
        uint256 _prixParPart
    )
        ERC20(nomPropriete, "FURSA")
        Ownable(msg.sender)
    {
        idProprieteBackend = _idBackend;
        nombreTotalParts   = _nombreParts;
        prixParPart        = _prixParPart;
        _mint(address(this), _nombreParts);
    }

    /// Une part est une unite indivisible : 0 decimale (sinon _mint(N) creerait N*10^-18 token).
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function acheterParts(uint256 nombreParts) external payable {
        require(nombreParts > 0, "Quantite invalide");
        require(msg.value == nombreParts * prixParPart, "Montant incorrect");
        require(balanceOf(address(this)) >= nombreParts, "Parts insuffisantes");
        _transfer(address(this), msg.sender, nombreParts);
        emit PartAchetee(msg.sender, nombreParts);
    }

    function partsDisponibles() external view returns (uint256) {
        return balanceOf(address(this));
    }
}