// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AssetToken is ERC20 {
    error AssetToken__onlyThunderLoan();
    error AssetToken__ExhangeRateCanOnlyIncrease(uint256 oldExchangeRate, uint256 newExchangeRate);
    error AssetToken__ZeroAddress();

    using SafeERC20 for IERC20;

    IERC20 private immutable i_underlying;        // it represents the actual ERC20, like USDT、USDC、ETH and so on
    address private immutable i_thunderLoan;      

    // The underlying per asset exchange rate
    // ie: s_exchangeRate = 2
    // means 1 asset token is worth 2 underlying tokens
    // 记录 基础资产underlying 和 AssetToken 之间的兑换率。
    // 这个兑换率表示 1 个 AssetToken 对应多少基础资产。初始兑换率为 1e18，即 1:1。
    uint256 private s_exchangeRate;
    uint256 public constant EXCHANGE_RATE_PRECISION = 1e18;
    uint256 private constant STARTING_EXCHANGE_RATE = 1e18;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ExchangeRateUpdated(uint256 newExchangeRate);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyThunderLoan() {
        if (msg.sender != i_thunderLoan) {
            revert AssetToken__onlyThunderLoan();
        }
        _;
    }

    modifier revertIfZeroAddress(address someAddress) {
        if (someAddress == address(0)) {
            revert AssetToken__ZeroAddress();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address thunderLoan,
        IERC20 underlying,              // 表示该 AssetToken 背后的实际基础资产，即支持 AssetToken 的真实 ERC20 代币
        string memory assetName,
        string memory assetSymbol
    )
        ERC20(assetName, assetSymbol)                   // 初始化 AssetToken
        revertIfZeroAddress(thunderLoan)
        revertIfZeroAddress(address(underlying))
    {
        i_thunderLoan = thunderLoan;
        i_underlying = underlying;
        s_exchangeRate = STARTING_EXCHANGE_RATE;        // 初始化 s_exchangeRate 为 1e18，即初始兑换率为 1
    }

    function mint(address to, uint256 amount) external onlyThunderLoan {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) external onlyThunderLoan {
        _burn(account, amount);
    }

    // 将基础资产（i_underlying）转移到指定地址
    function transferUnderlyingTo(address to, uint256 amount) external onlyThunderLoan {
        i_underlying.safeTransfer(to, amount);
    }

    // 该函数根据代币的总供应量和额外的手续费调整兑换率，确保兑换率只能增加，不能减少
    // 为了确保资产的价值能够随时间累积，并且代币持有者的权益不会因为通缩或费用分摊而减少
    // 资产代币（如 AssetToken）代表了用户在某个池子里的权益。当协议产生收入（如利息或费用）时，这些收益会自动反映在兑换率上，而不是直接分配给用户的账户余额。
    // 兑换率的持续增长能鼓励用户长期持有代币，因为代币持有者可以从不断增加的价值中获利。如果兑换率一直下降或波动剧烈，用户可能会失去持有的动力。

    function updateExchangeRate(uint256 fee) external onlyThunderLoan {
        // 1. Get the current exchange rate
        // 2. How big the fee is should be divided by the total supply
        // 3. So if the fee is 1e18, and the total supply is 2e18, the exchange rate be multiplied by 1.5
        // if the fee is 0.5 ETH, and the total supply is 4, the exchange rate should be multiplied by 1.125
        // it should always go up, never down

        // newExchangeRate = oldExchangeRate * (totalSupply + fee) / totalSupply
        // newExchangeRate = 1 (4 + 0.5) / 4
        // newExchangeRate = 1.125
        uint256 newExchangeRate = s_exchangeRate * (totalSupply() + fee) / totalSupply();

        if (newExchangeRate <= s_exchangeRate) {
            revert AssetToken__ExhangeRateCanOnlyIncrease(s_exchangeRate, newExchangeRate);
        }

        s_exchangeRate = newExchangeRate;

        emit ExchangeRateUpdated(s_exchangeRate);
    }

    function getExchangeRate() external view returns (uint256) {
        return s_exchangeRate;
    }

    function getUnderlying() external view returns (IERC20) {
        return i_underlying;
    }
}
