// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { LibSwap, InsufficientBalance } from "../Libraries/LibSwap.sol";
import { InvalidCaller, InsufficientBalance } from "../Errors/GenericErrors.sol";
import { LibAsset } from "../Libraries/LibAsset.sol";
import { ILiFi } from "../Interfaces/ILiFi.sol";
import { IExecutor } from "../Interfaces/IExecutor.sol";
import { TransferrableOwnership } from "../Helpers/TransferrableOwnership.sol";
import { IMessageReceiverApp } from"celer-network/contracts/message/interfaces/IMessageReceiverApp.sol";

//tmp
import { console } from "../../test/solidity/utils/Console.sol";      //TODO: remove
import { DSTest } from "ds-test/test.sol";      //TODO: remove


/// @title Executor
/// @author LI.FI (https://li.fi)
/// @notice Arbitrary execution contract used for cross-chain swaps and message passing
contract ReceiverCelerIM is DSTest, ILiFi, IMessageReceiverApp, ReentrancyGuard, TransferrableOwnership {
    using SafeERC20 for IERC20;

    /// Storage ///
    address public cBridgeMessageBusAddress;
    IExecutor public executor;

    /// Errors ///

    /// Events ///
    event CBridgeMessageBusAddressSet(address indexed messageBusAddress);

    /// Modifiers ///
    modifier onlyCBridgeMessageBus {
        if (msg.sender != cBridgeMessageBusAddress) revert InvalidCaller();
        _;
    }

    /// Constructor
    constructor(
        address _owner,
        address _cBridgeMessageBusAddress,
        address _executor
    ) TransferrableOwnership(_owner) {
        owner = _owner;
        cBridgeMessageBusAddress = _cBridgeMessageBusAddress;
        executor = IExecutor(_executor);
        emit CBridgeMessageBusAddressSet(_cBridgeMessageBusAddress);
    }

    /// External Methods ///


    /**
     * @notice Called by MessageBus to execute a message
     * @param _sender The address of the source app contract
     * @param _srcChainId The source chain ID where the transfer is originated from
     * @param _message Arbitrary message bytes originated from and encoded by the source app contract
     * @param _executor Address who called the MessageBus execution function
     */
    function executeMessage(
        address _sender,
        uint64 _srcChainId,
        bytes calldata _message,
        address _executor
    ) external payable override returns (IMessageReceiverApp.ExecutionStatus) {
        return _executeMessage(_sender, _srcChainId, _message, _executor);
    }

    // same as above, except that sender is an non-evm chain address,
    // otherwise same as above.
    function executeMessage(
        bytes calldata _sender,
        uint64 _srcChainId,
        bytes calldata _message,
        address _executor
    ) external payable override returns (IMessageReceiverApp.ExecutionStatus) {
            address sender = _bytesToAddress(_sender);      //! is this OK?
            return _executeMessage(sender, _srcChainId, _message, _executor);
    }


    function _executeMessage(        
        address _sender,
        uint64 _srcChainId,
        bytes calldata _message,
        address _executor
    ) private returns (IMessageReceiverApp.ExecutionStatus) {
        //TODO
    }

    /**
     * @notice Called by MessageBus to execute a message with an associated token transfer.
     * The Receiver is guaranteed to have received the right amount of tokens before this function is called.
     * @param _sender The address of the source app contract
     * @param _token The address of the token that comes out of the bridge
     * @param _amount The amount of tokens received at this contract through the cross-chain bridge.
     * @param _srcChainId The source chain ID where the transfer is originated from
     * @param _message Arbitrary message bytes originated from and encoded by the source app contract
     * @param _executor Address who called the MessageBus execution function
     */
    function executeMessageWithTransfer(
        address _sender,
        address _token,
        uint256 _amount,
        uint64 _srcChainId,
        bytes calldata _message,
        address _executor
    ) external payable returns (IMessageReceiverApp.ExecutionStatus) {
            emit log_string("");
            emit log_string("in executeMessageWithTransfer()");
            // make sure tokens have arrived        //TODO could be removed since it's guaranteed by MessageBus
            // uint256 balance = IERC20(_token).balanceOf(address(this));
            // if (balance < _amount) revert InsufficientBalance(_amount, balance);

            // decode message
            //! will this revert if data does not match the structure? >> NO
            (bytes32 transactionId, LibSwap.SwapData[] memory swapData, address receiver, address refundAddress) = 
                abi.decode(_message,(bytes32, LibSwap.SwapData[], address, address)
            );

            //TODO how to validate if data was correctly coded and decoded?

            // execute message/s
            _swapAndCompleteBridgeTokens(transactionId, swapData, _token, payable(receiver), _amount);

            return ExecutionStatus.Success;
    }

    /**
     * @notice Only called by MessageBus if
     *         1. executeMessageWithTransfer reverts, or
     *         2. executeMessageWithTransfer returns ExecutionStatus.Fail
     * The contract is guaranteed to have received the right amount of tokens before this function is called.
     * @param _sender The address of the source app contract
     * @param _token The address of the token that comes out of the bridge
     * @param _amount The amount of tokens received at this contract through the cross-chain bridge.
     * @param _srcChainId The source chain ID where the transfer is originated from
     * @param _message Arbitrary message bytes originated from and encoded by the source app contract
     * @param _executor Address who called the MessageBus execution function
     */
    function executeMessageWithTransferFallback(
        address _sender,
        address _token,
        uint256 _amount,
        uint64 _srcChainId,
        bytes calldata _message,
        address _executor
    ) external payable returns (IMessageReceiverApp.ExecutionStatus) {

            (bytes32 transactionId, LibSwap.SwapData[] memory swapData, address receiver, address refundAddress) = 
                abi.decode(_message,(bytes32, LibSwap.SwapData[], address, address)
            );
           
            // make sure contract has sufficient balance    //TODO could be removed
            uint256 balance = IERC20(_token).balanceOf(address(this));
            if (balance < _amount) revert InsufficientBalance(_amount, balance);

            // transfer tokens to receiver
            LibAsset.transferAsset(_token, payable(receiver), _amount);

            return ExecutionStatus.Success;
    }

    /**
     * @notice Called by MessageBus to process refund of the original transfer from this contract.
     * The contract is guaranteed to have received the refund before this function is called.
     * @param _token The token address of the original transfer
     * @param _amount The amount of the original transfer
     * @param _message The same message associated with the original transfer
     * @param _executor Address who called the MessageBus execution function
     */
    function executeMessageWithTransferRefund(
        address _token,
        uint256 _amount,
        bytes calldata _message,
        address _executor
    ) external payable onlyCBridgeMessageBus returns (IMessageReceiverApp.ExecutionStatus) {
            (bytes32 transactionId, LibSwap.SwapData[] memory swapData, address receiver, address refundAddress) = 
                abi.decode(_message,(bytes32, LibSwap.SwapData[], address, address)
            );
    
            // return funds to cBridgeData.refundAddress
            LibAsset.transferAsset(_token, payable(refundAddress), _amount);

            //TODO any events to be emitted here ??

            return ExecutionStatus.Success;
    }

    /// @notice set CBridge MessageBus address
    /// @param _messageBusAddress the MessageBus address
    function setCBridgeMessageBus(address _messageBusAddress) external onlyOwner {
        cBridgeMessageBusAddress = _messageBusAddress;
        emit CBridgeMessageBusAddressSet(_messageBusAddress);
    }

    // ------------------------------------------------------------------------------------------------

    /// Private Methods ///

    /// @notice Performs a swap before completing a cross-chain transaction
    /// @param _transactionId the transaction id associated with the operation
    /// @param _swapData array of data needed for swaps
    /// @param assetId token received from the other chain
    /// @param receiver address that will receive tokens in the end
    /// @param amount amount of token
    function _swapAndCompleteBridgeTokens(
        bytes32 _transactionId,
        LibSwap.SwapData[] memory _swapData,
        address assetId,
        address payable receiver,
        uint256 amount
    ) private {
        bool success;

        if (LibAsset.isNativeAsset(assetId)) {
            try executor.swapAndCompleteBridgeTokens{ value: amount }(_transactionId, _swapData, assetId, receiver) {
                success = true;
            } catch {
                receiver.call{ value: amount }("");
            }
        } else {
            IERC20 token = IERC20(assetId);
            token.safeApprove(address(executor), 0);
            token.safeIncreaseAllowance(address(executor), amount);

            try executor.swapAndCompleteBridgeTokens(_transactionId, _swapData, assetId, receiver) {
                success = true;
            } catch {
                // token.safeTransfer(receiver, amount);      // removed since this would break the CelerIM error/fallback flow 
            }

            token.safeApprove(address(executor), 0);    
            //TODO QUESTION: why do we have this line of code here if we set to 0 beforehand and expect
            //TODO           to use the whole given allowance anyway? 
        }

        if (!success) {
            emit LiFiTransferCompleted(_transactionId, assetId, receiver, amount, block.timestamp);
        }
    }

    function _bytesToAddress(bytes memory b) private pure returns(address payable a) {
        require(b.length == 20);
        assembly {
            a := div(mload(add(b, 32)), exp(256, 12))
        }
    }

}
