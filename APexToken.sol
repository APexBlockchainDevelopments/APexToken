pragma solidity ^0.8.4;

// SPDX-License-Identifier: Apache-2.0

/*
 █████╗ ██████╗ ███████╗██╗  ██╗    ████████╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗
██╔══██╗██╔══██╗██╔════╝╚██╗██╔╝    ╚══██╔══╝██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║
███████║██████╔╝█████╗   ╚███╔╝        ██║   ██║   ██║█████╔╝ █████╗  ██╔██╗ ██║
██╔══██║██╔═══╝ ██╔══╝   ██╔██╗        ██║   ██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║
██║  ██║██║     ███████╗██╔╝ ██╗       ██║   ╚██████╔╝██║  ██╗███████╗██║ ╚████║
╚═╝  ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝       ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝
*/

import "./SafeMath.sol";
import "./Address.sol";
import "./ERC20.sol";
import "./Ownable.sol";

contract APex is ERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;
    
    // Supply, limits and fees
    uint256 private constant TOTAL_SUPPLY = 100000000000000 * (10**9);

    uint256 public maxTxAmount = TOTAL_SUPPLY.mul(2).div(1000); // 2%


    uint256 public rewardsFee = 250; // 2%
    uint256 private _previousRewardsFee = rewardsFee;

    uint256 public burnFee = 250; // 2%
    uint256 private _burnFee = burnFee;

    // Prepared for launch
    bool private preparedForLaunch = false;

    // Blacklist
    mapping(address => bool) public isBlacklisted;
    
    // Exclusions
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcludedFromMaxTx;

    //Collector Wallet
    address public collectorWallet;
    

    //Events
    event MaxTxAmountUpdated(uint256 maxTxAmount);
    event GenericTransferChanged(bool useGenericTransfer);
    event ExcludeFromFees(address wallet);
    event IncludeInFees(address wallet);
    event collectorWalletUpdated(address newCollectorWallet);
    event FeesChanged(
        uint256 newRewardsFee,
        uint256 newBurnFee
    );
    event tokensBurned(uint256 amount);


    constructor() ERC20("APex Token", "APex") payable {
        
        // mint supply
        _mint(owner(), TOTAL_SUPPLY);

        // exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        
        // internal exclude from max tx
        _isExcludedFromMaxTx[owner()] = true;
        _isExcludedFromMaxTx[address(this)] = true;
        
    }
    
    function decimals() public view virtual override returns (uint8) {
        return 9;
    }
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {

        // blacklist
        require(
            !isBlacklisted[from] && !isBlacklisted[to],
            "Blacklisted address"
        );

        if(
            _isExcludedFromFee[from] &&
            _isExcludedFromFee[to] // by default false
        ){
            super._transfer(from, to, amount);
            return;
        }

        if (
            !_isExcludedFromMaxTx[from] &&
            !_isExcludedFromMaxTx[to] // by default false
        ) {
            require(
                amount <= maxTxAmount,
                "Transfer amount exceeds the maxTxAmount"
            );
        }


        (uint256 tTransferAmount, uint256 tFee) = _getValues(amount);
        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(tTransferAmount);

        _takeFee(tFee);
        burn(amount);

        emit Transfer(from, to, tTransferAmount);
    }


    receive() external payable {}  //do i need this?

    function _getValues(uint256 tAmount)
        private
        view
        returns (uint256, uint256)
    {
        uint256 tFee = calculateFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee);
        return (tTransferAmount, tFee);
    }

    function _takeFee(uint256 fee) private {
        _balances[address(this)] = _balances[address(this)].add(fee);
    }

    function calculateFee(uint256 _amount)
        private
        view
        returns (uint256)
    {
        uint256 totalFee = rewardsFee + burnFee; 
        return _amount.mul(totalFee).div(10000);
    }

    function burn(uint256 _amount) private {
        _burn(address(this), _amount.mul(burnFee).div(10000));
    }

    function blacklistAddress(address account, bool value) public onlyOwner {
        isBlacklisted[account] = value;
    }

    
    // for 0.5% input 5, for 1% input 10
    function setMaxTxPercent(uint256 newMaxTx) external onlyOwner {
        require(newMaxTx >= 5, "Max TX should be above 0.5%");
        maxTxAmount = TOTAL_SUPPLY.mul(newMaxTx).div(1000);
        emit MaxTxAmountUpdated(maxTxAmount);
    }
    
    function isExcludedFromFee(address account) external view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
        emit ExcludeFromFees(account);
    }

    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
        emit IncludeInFees(account);
    }


  function setFees(
        uint256 newBurnFee,
        uint256 newRewardsFee
    ) external onlyOwner {
        require(
            newBurnFee <= 1000 &&
            newRewardsFee <= 1000,
            "Fees exceed maximum allowed value"
        );
        rewardsFee = newBurnFee;
        burnFee = newRewardsFee;
        emit FeesChanged(newBurnFee, newRewardsFee);
    }

    //Monthly rewards functions
    function monthlyClaim() external{
        require(msg.sender == collectorWallet, "You are not allowed to do this");
        uint256 contractBalance = balanceOf(address(this));
        _transfer(address(this), collectorWallet, contractBalance);
    }

    function changeCollectorWallet(address _collectorWallet) external onlyOwner(){
        collectorWallet = _collectorWallet;
        excludeFromFee(_collectorWallet);
        emit collectorWalletUpdated(collectorWallet);
    }


    // emergency claim functions
    function manualClaim() external onlyOwner {  ///this should be changed to claim tokens
        uint256 contractBalance = balanceOf(address(this));
        _transfer(address(this), owner(), contractBalance);
    }

    function sendThetaToWallet(address wallet, uint256 amount) private {
        if (amount > 0) {
            payable(wallet).transfer(amount);
        }
    }

    function manualSend() external onlyOwner {
        uint256 contractEthBalance = address(this).balance;
        sendThetaToWallet(owner(), contractEthBalance);
    }
}