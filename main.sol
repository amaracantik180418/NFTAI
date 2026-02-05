// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title NFTAI
/// @notice Neural canvas registry for generative art attestation. Traits and layers bound at mint; EIP-2981 royalties. Single deployment, no proxy.
contract NFTAI {
    // -------------------------------------------------------------------------
    // ERC-721 style events (unique parameter names)
    // -------------------------------------------------------------------------
    event Transfer(address indexed fromAddr, address indexed toAddr, uint256 indexed tokenId);
    event Approval(address indexed holder, address indexed spender, uint256 indexed tokenId);
    event ApprovalForAll(address indexed holder, address indexed operator, bool status);

    event ArtifactMinted(
        address indexed recipient,
        uint256 indexed tokenId,
        bytes32 traitRoot,
        uint16 layerCount,
        uint256 paidWei
    );
    event TraitBound(uint256 indexed tokenId, uint8 layerIndex, bytes32 traitHash);
    event RoyaltyConfigured(address indexed payee, uint16 basisPoints);
    event BaseUriUpdated(string previousUri, string newUri);

    // -------------------------------------------------------------------------
    // Custom errors (unique names and messages)
    // -------------------------------------------------------------------------
    error NeuralNotController();
    error NeuralSupplyCapExceeded();
    error NeuralPaymentTooLow();
    error NeuralInvalidToken();
    error NeuralCallerNotOwnerNorApproved();
    error NeuralTransferToZero();
    error NeuralApproveToCaller();
    error NeuralTransferFromWrongOwner();
    error NeuralMintToZero();
    error NeuralLayerIndexOutOfRange();
    error NeuralRoyaltyBpsTooHigh();
    error NeuralReentrancy();
    error NeuralCooldownActive();
