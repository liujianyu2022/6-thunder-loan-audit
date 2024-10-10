// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

// 被调用的目标合约
contract Target {
    uint256 private num = 0;
    address private sender = address(0);

    function setVariables(uint256 _num, address _addr) public {
        num = _num;
        sender = _addr;
    }

    function getVariables() public view returns(uint256, address){
        return (num, sender);
    }
}


// 调用者合约
contract Caller {
    // 调用者合约 Caller 必须和目标合约 Target 的变量存储布局必须相同，两个变量，并且顺序为num和sender
    // 这是因为 delegatecall 会将被调用的合约逻辑执行在调用者合约的上下文中，即目标合约Target中的逻辑会使用调用者合约的存储。
    uint256 private num = 0;
    address private sender = address(0);

    // Caller合约的独立变量
    address target;


    constructor(address _target){
        target = _target;
    }


    // 通过call来调用Target合约的SetVariables()函数，将改变 Target合约 里的状态变量
    function callSetVariables(uint256 _num, address _addr) public{
        (bool success, ) = target.call(abi.encodeWithSignature("setVariables(uint256,address)", _num, _addr));
        require(success, "Low-level call failed");
    }

    // 通过delegatecall来调用Target合约的SetVariables()函数，将改变 Caller合约 自身的状态变量
    function delegateCallSetVariables(uint256 _num, address _addr) public {
       (bool success, ) = target.delegatecall(abi.encodeWithSignature("setVariables(uint256,address)", _num, _addr));
       require(success, "Low-level call failed");
    }

    function getVariables() public view returns(uint256, address){
        return (num, sender);
    }
}