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
        uint16 layerCount;
        uint64 mintedAt;
    }

    // -------------------------------------------------------------------------
    // Constructor (no args required; roles set to deployer)
    // -------------------------------------------------------------------------
    constructor() {
        controller = msg.sender;
        treasury = msg.sender;
        _royaltyPayee = msg.sender;
        _royaltyBps = uint16(ROYALTY_BPS_DEFAULT);
        genesisBlock = block.number;
        chainIdDeploy = block.chainid;
        _baseTokenURI = "ipfs://bafybeiaq7kh2vxeqnm4n2oq5r7k6f3m2p9s1t4u5v6w7x8y9z0a1b2c3d4e5f6/";
    }

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------
    modifier onlyController() {
        if (msg.sender != controller) revert NeuralNotController();
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyLock != 0) revert NeuralReentrancy();
        _reentrancyLock = 1;
        _;
        _reentrancyLock = 0;
    }

    // -------------------------------------------------------------------------
    // Metadata & config (view)
    // -------------------------------------------------------------------------
    function name() external pure returns (string memory) {
        return "NFTAI Artifacts";
    }

    function symbol() external pure returns (string memory) {
        return "NFTAI";
    }

    function baseTokenURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    function totalMinted() external view returns (uint256) {
        return _totalMinted;
    }

    function royaltyInfo(uint256 /* tokenId */, uint256 salePriceWei)
        external
        view
        returns (address receiver, uint256 royaltyAmountWei)
    {
        receiver = _royaltyPayee;
        royaltyAmountWei = (salePriceWei * uint256(_royaltyBps)) / 10_000;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == _INTERFACE_ID_ERC2981;
    }

    function getArtifactData(uint256 tokenId)
        external
        view
        returns (bytes32 traitRoot, uint16 layerCount, uint64 mintedAt)
    {
        if (_ownerOf[tokenId] == address(0)) revert NeuralInvalidToken();
        ArtifactData storage d = _artifactData[tokenId];
        return (d.traitRoot, d.layerCount, d.mintedAt);
    }

    function getMintCooldownBlocksLeft(address account) external view returns (uint256) {
        uint256 last = _lastMintBlockByAddress[account];
        if (last == 0) return 0;
        uint256 end = last + COOLDOWN_BLOCKS;
        if (block.number >= end) return 0;
        return end - block.number;
    }

    function nextTokenId() external view returns (uint256) {
        return _nextId;
    }

    function royaltyBps() external view returns (uint16) {
        return _royaltyBps;
    }

    function royaltyReceiver() external view returns (address) {
        return _royaltyPayee;
    }

    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY > _totalMinted ? MAX_SUPPLY - _totalMinted : 0;
    }

    // -------------------------------------------------------------------------
    // ERC-721 balance / ownership
    // -------------------------------------------------------------------------
    function balanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) revert NeuralTransferToZero();
        return _balanceOf[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _ownerOf[tokenId];
        if (owner == address(0)) revert NeuralInvalidToken();
        return owner;
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        if (_ownerOf[tokenId] == address(0)) revert NeuralInvalidToken();
        return _tokenApproval[tokenId];
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApproval[owner][operator];
    }

    // -------------------------------------------------------------------------
    // Mint (payable, with cooldown and supply cap)
    // -------------------------------------------------------------------------
    function mint(address to, bytes32 traitRoot, uint16 layerCount) external payable nonReentrant {
        if (to == address(0)) revert NeuralMintToZero();
        if (_totalMinted >= MAX_SUPPLY) revert NeuralSupplyCapExceeded();
        if (msg.value < MINT_PRICE_WEI) revert NeuralPaymentTooLow();
        if (layerCount > MAX_LAYERS_PER_TOKEN) revert NeuralLayerIndexOutOfRange();

        uint256 lastBlock = _lastMintBlockByAddress[msg.sender];
        if (lastBlock != 0 && block.number < lastBlock + COOLDOWN_BLOCKS) {
            revert NeuralCooldownActive();
        }
        _lastMintBlockByAddress[msg.sender] = block.number;

        uint256 tokenId = _nextId;
        _nextId += 1;
        _totalMinted += 1;

