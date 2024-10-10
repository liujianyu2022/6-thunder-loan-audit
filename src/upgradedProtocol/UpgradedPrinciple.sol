// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

// notion: upgradeable contract can not have the constructor !!
// storage  -->  proxy contract
// logic    -->  implementation contract
// Initializable contract to do something about storage !!

// 在Solidity中，可升级合约的核心原理是使用代理合约模式（Proxy Pattern），即通过将合约的逻辑与存储分离来实现。
// 这样即使逻辑合约发生变化，存储数据仍然保持不变，从而避免部署新的合约时数据丢失的问题。
// 1. 代理合约：代理合约负责与用户交互，同时转发调用到逻辑合约。它本身并不包含业务逻辑，只包含一个指向逻辑合约地址的存储变量。代理合约使用delegatecall将用户的调用转发给逻辑合约。
// 2. 逻辑合约：逻辑合约包含所有的业务逻辑函数。每次合约升级时，只需部署新的逻辑合约，而无需更改代理合约。代理合约通过存储的地址指向新的逻辑合约。
// 3. 存储数据分离：在使用delegatecall时，逻辑合约的函数在代理合约的上下文中执行，即使用代理合约的存储。这就确保了即使逻辑合约升级，原始的存储状态仍然保持不变。


// 存储合约：只负责存储数据，不包含任何业务逻辑。
contract Storage {
    int private a;
    int private b;
    int private result;

    function getA() external view returns (int) {
        return a;
    }

    function setA(int _a) external {
        a = _a;
    }

    function getB() external view returns (int) {
        return b;
    }

    function setB(int _b) external {
        b = _b;
    }

    function getResult() external view returns (int) {
        return result;
    }

    function setResult(int _result) external {
        result = _result;
    }
}

// 逻辑合约：只处理业务逻辑，不存储任何数据。代理合约通过delegatecall调用，由代理合约进行使用
contract LogicV1 {
    function sum(int _a, int _b) public pure returns (int256) {
        return _a + _b;
    }
}

contract LogicV2 {
    function sub(int _a, int _b) public pure returns (int256) {
        return _a - _b;
    } 
}

// 代理合约：负责将调用转发到逻辑合约，并管理存储合约的地址。
contract Proxy {
    address public logicContract;
    address public storageContract;

    // 在构造函数中初始化逻辑合约和存储合约的地址。
    constructor(address _logicContract, address _storageContract) {         
        logicContract = _logicContract;
        storageContract = _storageContract;
    }

    // 提供 updateLogic 函数来更新逻辑合约的地址，实现合约的升级。
    function updateLogic(address _newLogic) public {                   
        logicContract = _newLogic;
    }

    // 使用fallback函数转发所有调用
    fallback() external payable {

        // 获取参数并调用存储合约的setA和setB
        // msg.data[4:] 是一个切片操作，表示从 msg.data 字节数组的第 4 个字节开始提取数据。
        // 这里的 4 是因为在 Solidity 中，函数调用的前 4 个字节是函数选择器（function selector），用于指明被调用的函数
        // 举例：sum(int, int)，它的选择器是 bytes4(keccak256("sum(int256,int256)"))
        (int a, int b) = abi.decode(msg.data[4:], (int, int));
        Storage(storageContract).setA(a);
        Storage(storageContract).setB(b);

        // 在逻辑合约上进行delegatecall
        (bool success, bytes memory data) = logicContract.delegatecall(msg.data);

        require(success, "Delegatecall failed");

        Storage(storageContract).setResult(abi.decode(data, (int256)));

        // 将返回的数据返回给调用者
        assembly {
            return(add(data, 0x20), mload(data))
        }
    }

    receive() external payable {}
}
