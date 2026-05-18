// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

contract RevenueDistribution {

    struct Investisseur {
        uint dividend;
        bool exist;
    }

    address public owner;

    mapping(address => Investisseur) public Investors;
    address[] public InvestorsList;

    event InvestisseurAjouterEvent(address indexed investor);
    event DividendeVerseEvent(address indexed investor, uint amount);
    event PaiementRecuEvent(address indexed from, uint amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "seul owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // =========================
    // ADD INVESTOR (sans shares)
    // =========================
    function addInvestor(address _investor) public onlyOwner {
        require(!Investors[_investor].exist, "existe deja");

        Investors[_investor] = Investisseur({
            dividend: 0,
            exist: true
        });

        InvestorsList.push(_investor);

        emit InvestisseurAjouterEvent(_investor);
    }

    // =========================
    // PAY INVESTOR
    // =========================
    function payInvestor(address _investor, uint _amount) public onlyOwner {
        require(Investors[_investor].exist, "inexistant");
        require(_amount > 0, "montant invalide");
        require(address(this).balance >= _amount, "solde insuffisant");

        Investors[_investor].dividend += _amount;

        (bool success, ) = payable(_investor).call{value: _amount}("");
        require(success, "transfert echoue");

        emit DividendeVerseEvent(_investor, _amount);
    }

    // =========================
    // RECEIVE ETH
    // =========================
    function sendMoneyAInvestir() public payable {
        require(msg.value > 0, "ETH requis");
        emit PaiementRecuEvent(msg.sender, msg.value);
    }

    receive() external payable {
        emit PaiementRecuEvent(msg.sender, msg.value);
    }

    // =========================
    // WITHDRAW
    // =========================
    function withdraw() public {
        uint amount = Investors[msg.sender].dividend;
        require(amount > 0, "rien a retirer");

        Investors[msg.sender].dividend = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "echoue");
    }

    // =========================
    // READ FUNCTIONS
    // =========================
    function getDividende(address _investor) public view returns (uint) {
        return Investors[_investor].dividend;
    }

    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }
    
}