// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./TimeLockTransactions.sol";
import "./WithdrawableOwnable.sol";
import "./AntiDumpOwnable.sol";

/**
* Features:
*   Liquidity fee can go to all company. (Company configurable)
*   Enterprise ecosystem fee. (Company configurable)
*   Burn rate. (Company configurable up to a certain limit)
*   Total fees capped.
*   Dex volume based anti-whale anti dump fees. (Configurable to a certain extent by the company)
*   Time lock dex transactions.
*   Prevent people from creating dexpair without company authorization.
*/
contract HOMToken is ERC20, Ownable, TimeLockTransactions, WithdrawableOwnable, AntiDumpOwnable {
    using Address for address;

    // @dev dead address
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // @dev the fee the ecosystem takes. value uses decimals() as multiplicative factor
    uint256 public ecoSystemFee = 0;

    // @dev which wallet will receive the ecosystem fee
    address public ecoSystemAddress;

    // @dev the fee the liquidity takes. value uses decimals() as multiplicative factor
    uint256 public liquidityFee = 5 * 10**16; // 5%

    // @dev which wallet will receive the ecosystem fee. If dead is used, it goes to the msgSender
    address public liquidityAddress;

    // @dev the fee the burn takes. value uses decimals() as multiplicative factor
    uint256 public burnFee = 0; // 0%

    // @dev the max value of the ordinary fees sum
    uint256 public constant FEE_LIMIT = 2 * 10**17; // 20%

    // @dev the defauld dex router
    IUniswapV2Router02 public dexRouter;

    // @dev the dex factory address
    address public uniswapFactoryAddress;

    // @dev just to simplify to the user, the total fees
    uint256 public totalFees = 0;

    // @dev the total max value of the fees
    uint256 public numTokensSellToAddToLiquidity = 0;

    // @dev mapping of excluded from fees elements
    mapping(address => bool) public isExcludedFromFees;

    // @dev the default dex pair
    address public dexPair;

    // @dev what pairs are allowed to work in the token
    mapping(address => bool) public automatedMarketMakerPairs;

    constructor() ERC20("Heroes of Metaverse Token", "HOM") {
        uint256 initialSupply = 420000000 * 10**18;
        excludeFromFees(address(this), true);
        excludeFromFees(owner(), true);
        excludeFromFees(DEAD_ADDRESS, true);

        ecoSystemAddress = owner();
        liquidityAddress = DEAD_ADDRESS;

        _mint(owner(), initialSupply);

        numTokensSellToAddToLiquidity = initialSupply / (10**6); // 0.000001% of supply -> 420 tokens

        // Create a uniswap pair for this new token
        dexRouter = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // mainnet
        //        dexRouter = IUniswapV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1); // testnet

        dexPair = IUniswapV2Factory(dexRouter.factory()).createPair(address(this), dexRouter.WETH());
        _setAutomatedMarketMakerPair(dexPair, true);

        _updateTotalFee();

        emit ExcludeFromFees(owner(), true);
        emit ExcludeFromFees(address(this), true);
        emit ExcludeFromFees(DEAD_ADDRESS, true);
    }

    function setNumTokensLimitToAddToLiquidity(uint256 newLimit) external onlyOwner {
        require(newLimit >= totalSupply() / (10**6), "new limit is too low");
        numTokensSellToAddToLiquidity = newLimit;
        emit SetNumTokensSellToAddToLiquidity(newLimit);
    }
    event SetNumTokensSellToAddToLiquidity(uint256 newLimit);

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != dexPair, "default pair cannot be changed");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private onlyOwner {
        automatedMarketMakerPairs[pair] = value;
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    // @dev create and add a new pair for a given token
    function addNewPair(address tokenAddress) external onlyOwner returns (address np) {
        address newPair = IUniswapV2Factory(dexRouter.factory()).createPair(address(this), tokenAddress);
        _setAutomatedMarketMakerPair(newPair, true);
        emit AddNewPair(tokenAddress, newPair);
        return newPair;
    }
    event AddNewPair(address indexed tokenAddress, address indexed newPair);

    receive() external payable {}

    // @dev exclude an account to be taxed
    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(isExcludedFromFees[account] != excluded, "Already set");
        isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    // @dev internal use to checkif the total fee was reached
    function checkFeesChanged(uint256 _oldFee, uint256 _newFee) internal view {
        uint256 _fees = ecoSystemFee + liquidityFee + burnFee + _newFee - _oldFee;
        require(_fees <= FEE_LIMIT, "Fees exceeded max limitation");
    }

    // @dev set ecosystem address to receive fees
    function setEcoSystemAddress(address newAddress) external onlyOwner {
        require(ecoSystemAddress != newAddress, "EcoSystem address already setted");
        ecoSystemAddress = newAddress;
        emit EcoSystemAddressUpdated(newAddress);
    }

    // @dev set ecosystem tax to receive fees
    function setEcosystemFee(uint256 newFee) external onlyOwner {
        checkFeesChanged(ecoSystemFee, newFee);
        ecoSystemFee = newFee;
        _updateTotalFee();
        emit EcosystemFeeUpdated(newFee);
    }

    // @dev set liquidity address to receive fees, id dead, the lp token goes to the user
    function setLiquidityAddress(address newAddress) external onlyOwner {
        require(liquidityAddress != newAddress, "Liquidity address already setted");
        liquidityAddress = newAddress;
        emit LiquidityAddressUpdated(newAddress);
    }

    // @dev set liquidity tax
    function setLiquidityFee(uint256 newFee) external onlyOwner {
        checkFeesChanged(liquidityFee, newFee);
        liquidityFee = newFee;
        _updateTotalFee();
        emit LiquidityFeeUpdated(newFee);
    }

    // @set the liquidity fee
    function setBurnFee(uint256 newFee) external onlyOwner {
        checkFeesChanged(burnFee, newFee);
        burnFee = newFee;
        _updateTotalFee();
        emit BurnFeeUpdated(newFee);
    }

    function _updateTotalFee() internal {
        totalFees = liquidityFee + burnFee + ecoSystemFee;
    }

    function _swapAndLiquify(uint256 amount, address cakeReceiver) private {
        uint256 half = amount / 2;
        uint256 otherHalf = amount - half;  // token

        uint256 initialAmount = address(this).balance;

        _swapTokensForBNB(half);

        uint256 newAmount = address(this).balance - initialAmount;  // bnb

        _addLiquidity(otherHalf, newAmount, cakeReceiver);

        emit SwapAndLiquify(half, newAmount, otherHalf);
    }

    function _swapTokensForBNB(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WETH();

        _approve(address(this), address(dexRouter), tokenAmount);

        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, // The amount of input tokens to send.
            0, // The minimum amount of BNB that must be received for the transaction not to revert.
            path, // An array of token addresses. path.length must be >= 2. Pools for each consecutive pair of addresses must exist and have liquidity.
            address(this), // Recipient of the ETH.
            block.timestamp + 300 // Unix timestamp after which the transaction will revert.
        );
    }

    function _addLiquidity(uint256 tokenAmount, uint256 bnbAmount, address cakeReceiver) private {
        _approve(address(this), address(dexRouter), tokenAmount);

        dexRouter.addLiquidityETH{ value: bnbAmount }(
            address(this), // A pool token.
            tokenAmount, // The amount of token to add as liquidity if the WETH/token price is <= msg.value/amountTokenDesired (token depreciates).
            0, // Bounds the extent to which the WETH/token price can go up before the transaction reverts. Must be <= amountTokenDesired.
            0, // Bounds the extent to which the token/WETH price can go up before the transaction reverts. Must be <= msg.value.
            cakeReceiver, // Recipient of the liquidity tokens.
            block.timestamp + 300 // Unix timestamp after which the transaction will revert.
        );
    }

    function compareStrings(string memory a, string memory b) public pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    // @dev Protect against the usage of unauthorized pancake pairs. Reason: without this if someone creates another pair and this contract do not know it, all transactions will pass without dex fees on that given pair.
    modifier _checkIfPairIsAuthorized(address from, address to) {
        // if the contract has symbol and the name is Cake-LP, it is a pancake pair
        if(Address.isContract(from) && !automatedMarketMakerPairs[from]) {
            try IUniswapV2Pair(from).symbol() returns (string memory _value) {
                if(compareStrings(_value, "Cake-LP"))
                    revert("pair not allowed");
            }
            catch {}
        }
        if(Address.isContract(to) && !automatedMarketMakerPairs[to]) {
            try IUniswapV2Pair(to).symbol() returns (string memory _value) {
                if(compareStrings(_value, "Cake-LP"))
                    revert("pair not allowed");
            }
            catch {}
        }
        _;
    }

    function timeLockCheck(address from, address to) internal {
        if(automatedMarketMakerPairs[to])  // selling tokens
            lockIfCanOperateAndRevertIfNotAllowed(from);
        else if(automatedMarketMakerPairs[from]) // buying tokens
            lockIfCanOperateAndRevertIfNotAllowed(to);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override
    _checkIfPairIsAuthorized(from, to)
    {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (isExcludedFromFees[from] || isExcludedFromFees[to]) {
            super._transfer(from, to, amount);
        } else {
            // timelock dex transactions
            timeLockCheck(from,to);
            uint256 extraFee = 0;
            uint256 tokenToEcoSystem=0;
            uint256 tokensToLiquidity=0;
            uint256 tokensToBurn=0;

            // dex based fees
            // automatedMarketMakerPairs[from] -> buy tokens on dex
            // automatedMarketMakerPairs[to]   -> sell tokens on dex
            if(automatedMarketMakerPairs[to] || automatedMarketMakerPairs[from]) {
                // apply extra fee only on token sell operations
                if(automatedMarketMakerPairs[to])
                    extraFee = getAntiDumpFee(to,amount);

                // apply ecoSystemFee if enabled
                if (ecoSystemFee > 0 || extraFee > 0) {
                    tokenToEcoSystem = amount * (ecoSystemFee + extraFee) / (10 ** decimals());
                    super._transfer(from, ecoSystemAddress, tokenToEcoSystem);
                }

                // apply liquidity fee
                if (liquidityFee > 0) {
                    tokensToLiquidity = amount * liquidityFee / (10 ** decimals());
                    super._transfer(from, address(this), tokensToLiquidity);

                    // SELL _swapAndLiquify fails if we add liquidity and from == dexPair. it is a uniswap known issue
                    if(automatedMarketMakerPairs[to]){
                        // Company receives lp token
                        if(liquidityAddress != DEAD_ADDRESS){
                            if (balanceOf(address(this)) >= numTokensSellToAddToLiquidity)
                                _swapAndLiquify(balanceOf(address(this)), liquidityAddress);
                        }
                        // Cashback the user with LP token
                        else
                            _swapAndLiquify(tokensToLiquidity, from);
                    }
                    // The LP token from BUY and will be stored inside the contract until the company withdraws it
                }
            }

            // apply burn fees always
            if (burnFee > 0) {
                tokensToBurn = amount * (burnFee) / (10 ** decimals());
                super._transfer(from, DEAD_ADDRESS, tokensToBurn);
            }

            uint256 amountMinusFees = amount - tokenToEcoSystem - tokensToLiquidity - tokensToBurn;
            super._transfer(from, to, amountMinusFees);
        }
    }

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event LiquidityAddressUpdated(address indexed liquidityAddress);
    event EcoSystemAddressUpdated(address indexed ecoSystemAddress);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SwapAndLiquify(
        uint256 indexed tokensSwapped,
        uint256 indexed bnbReceived,
        uint256 indexed tokensIntoLiqudity
    );
    event EcosystemFeeUpdated(uint256 indexed fee);
    event LiquidityFeeUpdated(uint256 indexed fee);
    event BurnFeeUpdated(uint256 indexed fee);
}