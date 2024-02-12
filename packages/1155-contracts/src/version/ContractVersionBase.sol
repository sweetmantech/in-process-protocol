// This file is automatically generated by code; do not manually update
// Last updated on 2024-02-12T22:39:13.769Z
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IVersionedContract} from "../interfaces/IVersionedContract.sol";

/// @title ContractVersionBase
/// @notice Base contract for versioning contracts
contract ContractVersionBase is IVersionedContract {
    /// @notice The version of the contract
    function contractVersion() external pure override returns (string memory) {
        return "2.7.1";
    }
}
