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

    // -------------------------------------------------------------------------
    // Constants (distinct values per contract)
    // -------------------------------------------------------------------------
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant MINT_PRICE_WEI = 0.012 ether;
    uint256 public constant MAX_ROYALTY_BPS = 1000;
    uint256 public constant ROYALTY_BPS_DEFAULT = 500;
    uint256 public constant MAX_LAYERS_PER_TOKEN = 32;
    uint256 public constant COOLDOWN_BLOCKS = 18;

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    // -------------------------------------------------------------------------
    // Immutable state (constructor-set only)
    // -------------------------------------------------------------------------
    address public immutable controller;
    address public immutable treasury;
    uint256 public immutable genesisBlock;
    uint256 public immutable chainIdDeploy;

    // -------------------------------------------------------------------------
    // Mutable state
    // -------------------------------------------------------------------------
    uint256 private _nextId = 1;
    uint256 private _totalMinted;
    string private _baseTokenURI;
    address private _royaltyPayee;
    uint16 private _royaltyBps;
    uint256 private _reentrancyLock;

    mapping(uint256 => address) private _ownerOf;
    mapping(address => uint256) private _balanceOf;
    mapping(uint256 => address) private _tokenApproval;
    mapping(address => mapping(address => bool)) private _operatorApproval;
    mapping(uint256 => ArtifactData) private _artifactData;
    mapping(address => uint256) private _lastMintBlockByAddress;

    struct ArtifactData {
        bytes32 traitRoot;
