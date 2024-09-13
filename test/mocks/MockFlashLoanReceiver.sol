// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IFlashLoanReceiver, IThunderLoan } from "../../src/interfaces/IFlashLoanReceiver.sol";

contract MockFlashLoanReceiver {
    error MockFlashLoanReceiver__onlyOwner();
    error MockFlashLoanReceiver__onlyThunderLoan();

    using SafeERC20 for IERC20;

    address s_owner;                            // 合约的所有者地址 msg.sender
    address s_thunderLoan;                      // 保存 ThunderLoan 合约的地址

    uint256 s_balanceDuringFlashLoan;
    uint256 s_balanceAfterFlashLoan;

    constructor(address thunderLoan) {
        s_owner = msg.sender;
        s_thunderLoan = thunderLoan;
        s_balanceDuringFlashLoan = 0;
    }

    function executeOperation(
        address token,                      // 闪电贷的代币
        uint256 amount,
        uint256 fee,                        // 闪电贷的费用
        address initiator,                  // 发起闪电贷的调用者（即合约所有者）
        bytes calldata /*  params */
    )
        external
        returns (bool)
    {
        s_balanceDuringFlashLoan = IERC20(token).balanceOf(address(this));

        // 检查 initiator 是否为合约的所有者（s_owner）
        if (initiator != s_owner) {
            revert MockFlashLoanReceiver__onlyOwner();
        }

        // 检查 msg.sender 是否为 ThunderLoan 合约地址（s_thunderLoan）
        // this method is called by thunderLoan
        if (msg.sender != s_thunderLoan) {
            revert MockFlashLoanReceiver__onlyThunderLoan();
        }

        // now, you have the borrowed funds, you can peform any operations you wish here !!

        // 批准并归还闪电贷
        IERC20(token).approve(s_thunderLoan, amount + fee);
        IThunderLoan(s_thunderLoan).repay(token, amount + fee);


        s_balanceAfterFlashLoan = IERC20(token).balanceOf(address(this));

        return true;
    }

    function getBalanceDuring() external view returns (uint256) {
        return s_balanceDuringFlashLoan;
    }

    function getBalanceAfter() external view returns (uint256) {
        return s_balanceAfterFlashLoan;
    }
}
