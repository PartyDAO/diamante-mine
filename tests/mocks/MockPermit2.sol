// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mocks the behavior of Uniswap's Permit2 contract for testing purposes.
// It allows transfers without signature verification.
contract MockPermit2 is ISignatureTransfer {
    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata // signature - ignored for mock
    )
        external
        virtual
    {
        IERC20(permit.permitted.token).transferFrom(owner, transferDetails.to, transferDetails.requestedAmount);
    }

    function permitTransferFrom(
        PermitBatchTransferFrom calldata permit,
        SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes calldata // signature
    )
        external
        virtual
    {
        for (uint256 i = 0; i < transferDetails.length; i++) {
            IERC20(permit.permitted[i].token).transferFrom(owner, transferDetails[i].to, permit.permitted[i].amount);
        }
    }

    function permitWitnessTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32, // witness
        string calldata, // witnessTypeString
        bytes calldata // signature
    )
        external
        virtual
    {
        this.permitTransferFrom(permit, transferDetails, owner, "");
    }

    function permitWitnessTransferFrom(
        PermitBatchTransferFrom calldata permit,
        SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes32, // witness
        string calldata, // witnessTypeString
        bytes calldata // signature
    )
        external
        virtual
    {
        this.permitTransferFrom(permit, transferDetails, owner, "");
    }

    function allowance(
        address,
        address,
        address
    )
        external
        view
        virtual
        returns (uint160 amount, uint48 expiration, uint48 nonce)
    {
        // Return max allowance for tests to pass checks
        return (type(uint160).max, type(uint48).max, 0);
    }

    function nonceBitmap(address, uint256) external view virtual returns (uint256) {
        return 0;
    }

    function invalidateUnorderedNonces(uint256, uint256) external virtual {
        // Mock implementation, does nothing.
    }

    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return bytes32(0);
    }
}
