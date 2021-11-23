// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
}

library StringHelper {
    function concat(
        bytes memory a,
        bytes memory b
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(a, b);
    }
    
    function toStringBytes(uint256 v) internal pure returns (bytes memory) {
        if (v == 0) { return "0"; }

        uint256 j = v;
        uint256 len;

        while (j != 0) {
            len++;
            j /= 10;
        }

        bytes memory bstr = new bytes(len);
        uint256 k = len - 1;
        
        while (v != 0) {
            bstr[k--] = byte(uint8(48 + v % 10));
            v /= 10;
        }
        
        return bstr;
    }
    
    
    function getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        if (_returnData.length < 68) return 'Transaction reverted silently';
    
        assembly {
            _returnData := add(_returnData, 0x04)
        }

        return abi.decode(_returnData, (string));
    }
}

contract TokenSwapWith0x {
    using StringHelper for bytes;
    using StringHelper for uint256;

    string private api0xUrl = 'https://kovan.api.0x.org/swap/v1/quote';
    string private wethToDai0xApiRequest = '?sellToken=0xd0A1E359811322d97991E03f863a0C30C2cF029C&buyToken=0x1528f3fcc26d13f7079325fb78d9442607781c8c&buyAmount=';
    
    IWETH public immutable WETH = IWETH(0xd0A1E359811322d97991E03f863a0C30C2cF029C);
    IERC20 public immutable DAI = IERC20(0x1528F3FCc26d13F7079325Fb78D9442607781c8C);
    
    function get0xApiRequest(uint256 paymentAmountInDai) external view returns(string memory) {
        return string(bytes(api0xUrl).concat(bytes(wethToDai0xApiRequest)).concat(paymentAmountInDai.toStringBytes()));
    }

    function pay(
        uint256 paymentAmountInDai,
        address spender,
        address payable swapTarget,
        bytes calldata swapCallData
    ) public payable {
      if (msg.value > 0) {
          _convertEthToDai(paymentAmountInDai, spender, swapTarget, swapCallData);
      } else {
          require(spender == address(0), "EMPTY_SPENDER_WITHOUT_SWAP");
          require(swapTarget == address(0), "EMPTY_TARGET_WITHOUT_SWAP");
          require(swapCallData.length == 0, "EMPTY_CALLDATA_WITHOUT_SWAP");
          require(DAI.transferFrom(msg.sender, address(this), paymentAmountInDai));
      }
      // do something with that DAI
      // ...
    }

    function _convertEthToDai(
        uint256 paymentAmountInDai,
        address spender, // The `allowanceTarget` field from the API response.
        address payable swapTarget, // The `to` field from the API response.
        bytes calldata swapCallData // The `data` field from the API response.
    ) private {
        WETH.deposit{value: msg.value}();
    
        uint256 currentDaiBalance = DAI.balanceOf(address(this));
        require(WETH.approve(spender, type(uint256).max), "approve failed");
    
        (bool success, bytes memory res) = swapTarget.call(swapCallData);
        require(success, string(bytes('SWAP_CALL_FAILED: ').concat(bytes(res.getRevertMsg()))));
        
        msg.sender.transfer(address(this).balance);

        uint256 boughtAmount = DAI.balanceOf(address(this)) - currentDaiBalance;
        require(boughtAmount >= paymentAmountInDai, "INVALID_BUY_AMOUNT");
        
        // uint256 daiRefund = boughtAmount - paymentAmountInDai;
        // DAI.transfer(msg.sender, daiRefund);
    }

    // required for refunds
    receive() external payable {}
}
