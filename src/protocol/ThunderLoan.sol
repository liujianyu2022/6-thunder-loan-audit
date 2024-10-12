// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AssetToken } from "./AssetToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OracleUpgradeable } from "./OracleUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IFlashLoanReceiver } from "../interfaces/IFlashLoanReceiver.sol";

contract ThunderLoan is Initializable, OwnableUpgradeable, UUPSUpgradeable, OracleUpgradeable {
    error ThunderLoan__NotAllowedToken(IERC20 token);
    error ThunderLoan__CantBeZero();
    error ThunderLoan__NotPaidBack(uint256 expectedEndingBalance, uint256 endingBalance);
    error ThunderLoan__NotEnoughTokenBalance(uint256 startingBalance, uint256 amount);
    error ThunderLoan__CallerIsNotContract();
    error ThunderLoan__AlreadyAllowed();
    error ThunderLoan__ExhangeRateCanOnlyIncrease();
    error ThunderLoan__NotCurrentlyFlashLoaning();
    error ThunderLoan__BadNewFee();

    using SafeERC20 for IERC20;
    using Address for address;

    // underlyingToken => AssetToken
    mapping(IERC20 => AssetToken) public s_tokenToAssetToken;

    // The fee in WEI, it should have 18 decimals. Each flash loan takes a flat fee of the token price.
    // it should be immutable or constant because it never changed after deployment.
    uint256 private s_feePrecision; 
    uint256 private s_flashLoanFee; // 0.3% ETH fee

    mapping(IERC20 token => bool currentlyFlashLoaning) private s_currentlyFlashLoaning;

    event Deposit(address indexed account, IERC20 indexed token, uint256 amount);
    event AllowedTokenSet(IERC20 indexed token, AssetToken indexed asset, bool allowed);
    event Redeemed(
        address indexed account, IERC20 indexed token, uint256 amountOfAssetToken, uint256 amountOfUnderlying
    );
    event FlashLoan(address indexed receiverAddress, IERC20 indexed token, uint256 amount, uint256 fee, bytes params);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier revertIfZero(uint256 amount) {
        if (amount == 0) {
            revert ThunderLoan__CantBeZero();
        }
        _;
    }

    modifier revertIfNotAllowedToken(IERC20 token) {
        if (!isAllowedToken(token)) {
            revert ThunderLoan__NotAllowedToken(token);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // what happens if we deploy the contract, and someone else initializes it?
    // that would suck, and they can pick a different poolFactoryAddress.
    // the OnlyInitialized modifier can be used to prevent the front run.
    function initialize(address poolFactoryAddress) external initializer {
        __Ownable_init(msg.sender);         // function __Ownable_init(address initialOwner) internal onlyInitializing             
        __UUPSUpgradeable_init();
        __Oracle_init(poolFactoryAddress);                // 继承于 OracleUpgradedable.sol
        s_feePrecision = 1e18;
        s_flashLoanFee = 3e15; // 0.3% ETH fee
    }

    // 用户可以将指定的ERC-20代币存入合约，并获得对应的资产代币（AssetToken），用于表示用户的存款权益
    // the user is the liquidity provider !!!
    function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token];             // AssetToken represents the share of the pool

        uint256 exchangeRate = assetToken.getExchangeRate();

        // EXCHANGE_RATE_PRECISION / exchangeRate <= 1
        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
        emit Deposit(msg.sender, token, amount);
        assetToken.mint(msg.sender, mintAmount);

        // 存款的时候不需要更新 exchangeRate，只有在其他用户进行闪电贷的时候获取fee后才更新
        // uint256 calculatedFee = getCalculatedFee(token, amount);
        // assetToken.updateExchangeRate(calculatedFee);

        // (from, to, amount)
        // the user transfer amount tokens to assetToken contract
        // the money is stored in the AssetToken Contract
        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }

    /// @notice Withdraws the underlying token from the asset token
    /// @param token The token they want to withdraw from
    /// @param amountOfAssetToken The amount of the underlying they want to withdraw
    function redeem(IERC20 token, uint256 amountOfAssetToken) external revertIfZero(amountOfAssetToken) revertIfNotAllowedToken(token){

        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();

        if (amountOfAssetToken == type(uint256).max) {
            amountOfAssetToken = assetToken.balanceOf(msg.sender);
        }

        // exchangeRate / EXCHANGE_RATE_PRECISION >= 1
        uint256 amountUnderlying = (amountOfAssetToken * exchangeRate) / assetToken.EXCHANGE_RATE_PRECISION();

        emit Redeemed(msg.sender, token, amountOfAssetToken, amountUnderlying);

        assetToken.burn(msg.sender, amountOfAssetToken);
        assetToken.transferUnderlyingTo(msg.sender, amountUnderlying);
    }

    function flashloan(
        address receiverAddress,                    // 在闪电贷场景中，借款人合约会实现 IFlashLoanReceiver 接口
        IERC20 token,                               // 借贷的ERC-20代币
        uint256 amount, 
        bytes calldata params                       // 附加的操作参数
    ) external revertIfZero(amount) revertIfNotAllowedToken(token){
        
        AssetToken assetToken = s_tokenToAssetToken[token];
        
        uint256 startingBalance = IERC20(token).balanceOf(address(assetToken));     // 记录初始合约的代币余额

        if (amount > startingBalance) {
            revert ThunderLoan__NotEnoughTokenBalance(startingBalance, amount);
        }

        if (receiverAddress.code.length == 0) {
            revert ThunderLoan__CallerIsNotContract();
        }

        uint256 fee = getCalculatedFee(token, amount);
        // slither-disable-next-line reentrancy-vulnerabilities-2 reentrancy-vulnerabilities-3
        assetToken.updateExchangeRate(fee);

        emit FlashLoan(receiverAddress, token, amount, fee, params);

        s_currentlyFlashLoaning[token] = true;                                      // 标记为正在进行闪电贷，防止重入攻击
        assetToken.transferUnderlyingTo(receiverAddress, amount);                   // 将借款的代币发送给接收者（借款人）

        // 借款人合约必须实现该接口，以便在闪电贷期间接收代币并执行操作
        // executeOperation 函数在闪电贷借款发生后立即被调用，借款人可以在该函数中使用借入的资金进行任何合法的操作
        // interface IFlashLoanReceiver {
        //     function executeOperation(
        //         IERC20 token,
        //         uint256 amount,
        //         uint256 fee,                 // 闪电贷费用
        //         address initiator,           // 闪电贷的发起人地址
        //         bytes calldata params
        //     ) external;
        // }

        // receiverAddress.functionCall(bytes memory data)       data 是通过 ABI 编码的函数签名和参数
        // 是一个低级调用方式，用于调用 receiverAddress 代表的外部合约地址上的某个函数。它提供了比直接使用 call 更加安全的方式来执行外部合约的函数。
        // functionCall 是 Solidity 中 Address 库的一部分，能够通过地址进行安全的合约调用，并带有失败处理机制。

        // bytes memory data = abi.encodeWithSignature(
        //     "executeOperation(address,uint256,uint256,address,bytes)", 
        //     token, amount, fee, msg.sender, params
        // );
        // (bool success, bytes memory returnData) = receiverAddress.call(data);

        // bytes memory data = abi.encodeWithSelector(
        //     IFlashLoanReceiver.executeOperation.selector,                        // 提取函数选择器
        //     token, amount, fee, msg.sender, params
        // );
        // (bool success, bytes memory returnData) = receiverAddress.call(data);


        // abi.encodeCall(functionSignature, (parameters))      其中 functionSignature 是函数名和参数类型，parameters 是具体的函数参数
        // abi.encodeCall 是 Solidity 0.8 版本引入的新功能，专门用于对外部合约的函数调用进行 ABI 编码

        // slither-disable-next-line unused-return reentrancy-vulnerabilities-2
        receiverAddress.functionCall(
            abi.encodeCall(
                IFlashLoanReceiver.executeOperation,       // 调用借款人合约的回调函数 executeOperation，允许借款人在交易过程中执行其他操作
                (
                    address(token),
                    amount,
                    fee,
                    msg.sender, // initiator
                    params
                )
            )
        );

        uint256 endingBalance = token.balanceOf(address(assetToken));               // 检查借款后合约代币的余额

        // 确保借款人在操作后偿还了借款和费用
        if (endingBalance < startingBalance + fee) {                    
            revert ThunderLoan__NotPaidBack(startingBalance + fee, endingBalance);
        }

        s_currentlyFlashLoaning[token] = false;                                     // 闪电贷操作结束，允许新的闪电贷
    }

    // 允许用户偿还通过 闪电贷 (flashloan) 借到的资金
    // IERC20 token     借款时使用的 IERC20 代币合约的地址，用来指定偿还的代币种类
    function repay(IERC20 token, uint256 amount) public {

        // 通过 s_currentlyFlashLoaning[token] 检查对应 token 是否在当前正在进行闪电贷操作。如果不是，则抛出错误，表明当前没有进行闪电贷。
        // 用来追踪哪些代币正在被用于闪电贷。这个检查是为了确保只有在闪电贷活动中的代币才能进行偿还
        if (!s_currentlyFlashLoaning[token]) {
            revert ThunderLoan__NotCurrentlyFlashLoaning();
        }

        AssetToken assetToken = s_tokenToAssetToken[token];

        // 使用 safeTransferFrom 方法从调用者 (msg.sender) 的账户中将 amount 数量的 token 代币转移到 assetToken 合约地址。
        // 这意味着还款的金额将由 AssetToken 合约管理
        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }

    // 当允许某个代币用于闪电贷操作时，创建并返回与该代币相关的 AssetToken 合约，同时设置名称和符号
    // 当不允许某个代币用于闪电贷时，删除该代币与其 AssetToken 之间的映射，并返回被删除的 AssetToken
    // 通过这个函数，合约所有者可以动态地管理哪些代币能够被用于闪电贷操作
    function setAllowedToken(IERC20 token, bool allowed) external onlyOwner returns (AssetToken) {
        if (allowed) {

            if (address(s_tokenToAssetToken[token]) != address(0)) {
                revert ThunderLoan__AlreadyAllowed();
            }

            string memory name = string.concat("ThunderLoan ", IERC20Metadata(address(token)).name());
            string memory symbol = string.concat("tl", IERC20Metadata(address(token)).symbol());

            // (address thunderLoan, IERC20 underlying, string memory assetName, string memory assetSymbol)
            AssetToken assetToken = new AssetToken(address(this), token, name, symbol);
            s_tokenToAssetToken[token] = assetToken;

            emit AllowedTokenSet(token, assetToken, allowed);
            return assetToken;                                          // 返回创建的 AssetToken 合约实例

        } else {

            AssetToken assetToken = s_tokenToAssetToken[token];
            delete s_tokenToAssetToken[token];
            emit AllowedTokenSet(token, assetToken, allowed);
            return assetToken;
        }
    }

    function getCalculatedFee(IERC20 token, uint256 amount) public view returns (uint256 fee) {
        // getPriceInWeth 函数获取 token 代币相对于 WETH（Wrapped Ether）的价格，可能是通过某个价格预言机或其他定价机制实现的。
        // 将 amount 和该代币的价格相乘，得出借贷代币的价值（valueOfBorrowedToken）。然后将结果除以 s_feePrecision，以保持精度。

        //slither-disable-next-line divide-before-multiply
        uint256 valueOfBorrowedToken = (amount * getPriceInWeth(address(token))) / s_feePrecision;

        //slither-disable-next-line divide-before-multiply
        fee = (valueOfBorrowedToken * s_flashLoanFee) / s_feePrecision;     // fee = valueOfBorrowedToken * 0.3%
    }

    function updateFlashLoanFee(uint256 newFee) external onlyOwner {
        if (newFee > s_feePrecision) {
            revert ThunderLoan__BadNewFee();
        }
        s_flashLoanFee = newFee;
    }

    function isAllowedToken(IERC20 token) public view returns (bool) {
        return address(s_tokenToAssetToken[token]) != address(0);
    }

    function getAssetFromToken(IERC20 token) public view returns (AssetToken) {
        return s_tokenToAssetToken[token];
    }

    function isCurrentlyFlashLoaning(IERC20 token) public view returns (bool) {
        return s_currentlyFlashLoaning[token];
    }

    function getFee() external view returns (uint256) {
        return s_flashLoanFee;
    }

    function getFeePrecision() external view returns (uint256) {
        return s_feePrecision;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
}
