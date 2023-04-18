//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract Megan is ReentrancyGuard, Ownable{
    IERC20 public sowl;
    address public transferedAddress;

    mapping(uint8 => uint256) private levelsPerTier;
    mapping(uint256 => bool) private tiers;
    mapping(bytes => bool) private signatureUsed;
    mapping(uint256 => uint256) private buyAmount;
    mapping(uint256 => bool) private isbuyAmountSet;
    mapping(address => mapping(uint8 => User)) private user;
    mapping(uint8 => mapping(uint8 => bool)) private levels;
    mapping(uint8 => mapping(uint8 => bool)) private isRewardSet;
    mapping(uint256 => mapping(uint256 => uint256)) private rewards;

    event TierBought(IERC20 sowl, address indexed _from, address indexed _to, uint8 indexed _tier);
    event LevelCompleted(IERC20 sowl, address indexed _from, uint8 indexed _tier, uint8 _level, uint256 _rewardsEarned);
    event RewardClaimed(IERC20 sowl, address indexed _from, address indexed _to, uint8 indexed _tier, uint8 _level, uint256 _rewardsClaimed);

    struct User {
        address userAddress;
        uint8 tiersBought;
        uint8[] levelsCompleted;
        uint256 rewardsEarned;
        mapping(uint8 => bool) isLevelCompleted;
        bool isUserBoughtTier;
        mapping(uint8 => bool) rewardsCanClaim;
        mapping(uint8 => bool) rewardsClaimed;
    }

    constructor(address _sowl, address _transferedAddress) {
        require(_transferedAddress != address(0), "Address cannot be 0");
        sowl = IERC20(_sowl);
        transferedAddress = _transferedAddress;
    }

    function buyTier(uint8 _tier, bytes32 hash, bytes memory signature) external nonReentrant {
        require(tiers[_tier], "Tier does not exists");
        require(
            recoverSigner(hash, signature) == owner(),
            "Address is not authorized"
        );
        require(!signatureUsed[signature], "Already signature used");
        require(user[msg.sender][_tier].isUserBoughtTier == false, "Cannot buy tier");
        require(isbuyAmountSet[_tier], "Buy amount is not set");
        require(sowl.balanceOf(msg.sender) >= buyAmount[_tier], "Not enough sowl tokens");
        require(
            sowl.allowance(msg.sender, address(this)) >= buyAmount[_tier],
            "Check the sowl token allowance"
        );
        user[msg.sender][_tier].userAddress = msg.sender;
        user[msg.sender][_tier].tiersBought = _tier;
        user[msg.sender][_tier].isUserBoughtTier = true;
        signatureUsed[signature] = true;
        SafeERC20.safeTransferFrom(sowl, msg.sender, transferedAddress, buyAmount[_tier]);
        emit TierBought(sowl, msg.sender, transferedAddress, _tier);
    }

    function levelCompleted(uint8 _tier, uint8 _level, bytes32 hash, bytes memory signature) external {
        require(tiers[_tier], "Tier does not exists");
        require(levels[_tier][_level], "Level does not exists");
        require(user[msg.sender][_tier].tiersBought == _tier, "Please buy tier");
        require(
            recoverSigner(hash, signature) == owner(),
            "Address is not authorized"
        );
        require(!signatureUsed[signature], "Already signature used");
        require(!user[msg.sender][_tier].isLevelCompleted[_level], "Level already completed");
        // Check if user has completed all previous levels
        for (uint8 i = 0; i < _level; i++) {
            require(user[msg.sender][_tier].isLevelCompleted[i], "Previous level not completed");
        }
        user[msg.sender][_tier].levelsCompleted.push(_level);
        user[msg.sender][_tier].rewardsEarned += rewards[_tier][_level];
        user[msg.sender][_tier].isLevelCompleted[_level] = true;
        user[msg.sender][_tier].rewardsCanClaim[_level] = true;
        if(levelsPerTier[_tier] == user[msg.sender][_tier].levelsCompleted.length){
            for (uint i = 0; i < user[msg.sender][_tier].levelsCompleted.length; i++) {
                uint8 completedLevel = user[msg.sender][_tier].levelsCompleted[i];
                user[msg.sender][_tier].isLevelCompleted[completedLevel] = false;
            }
            delete user[msg.sender][_tier].levelsCompleted;
            user[msg.sender][_tier].isUserBoughtTier = false;
        }
        signatureUsed[signature] = true;
        emit LevelCompleted(sowl, msg.sender, _tier, _level, rewards[_tier][_level]);
    }

    function claimReward(uint8 _tier, uint8 _level, bytes32 hash, bytes memory signature) external nonReentrant {
        require(tiers[_tier], "Tier does not exist");
        require(levels[_tier][_level], "Level does not exists");
        require(isRewardSet[_tier][_level], "Reward not set");
        require(
            recoverSigner(hash, signature) == owner(),
            "Address is not authorized"
        );
        require(!signatureUsed[signature], "Already signature used");
        require(user[msg.sender][_tier].rewardsCanClaim[_level], "Cannot claim the reward");
        require(sowl.balanceOf(address(this)) >= user[msg.sender][_tier].rewardsEarned, "Not enough sowl tokens");
        require(!user[msg.sender][_tier].rewardsClaimed[_level], "Already claimed");
        user[msg.sender][_tier].rewardsEarned -= rewards[_tier][_level];
        SafeERC20.safeTransfer(sowl, msg.sender, user[msg.sender][_tier].rewardsEarned);
        user[msg.sender][_tier].rewardsClaimed[_level] = true;
        signatureUsed[signature] = true;
        emit RewardClaimed(sowl, address(this), msg.sender, _tier, _level, user[msg.sender][_tier].rewardsEarned);
    }

    function addTier(uint8 _tier, uint256 _buyAmount) onlyOwner external {
        require(!tiers[_tier], "Tier already exists");
        require(_buyAmount > 0, "Invalid parameter"); 
        buyAmount[_tier] = _buyAmount;
        tiers[_tier] = true;
        isbuyAmountSet[_tier] = true;
    }

    function addLevel(uint8 _tier, uint8 _level, uint256 _rewards) onlyOwner external {
        require(tiers[_tier], "Level does not exist");
        require(!levels[_tier][_level], "Level already exists");
        require(_rewards > 0, "Invalid parameter"); 
        rewards[_tier][_level] = _rewards;
        levelsPerTier[_tier] += 1;
        levels[_tier][_level] = true;
        isRewardSet[_tier][_level] = true;
    
    }

    function addTiers(uint8[] memory _tiers, uint256[] memory _buyAmounts) external onlyOwner {
        require(_tiers.length == _buyAmounts.length, "Invalid buyAmounts length");
        for (uint i = 0; i < _tiers.length; i++) {
            uint8 tier = _tiers[i];
            require(!tiers[tier], "Tier already exists");
            tiers[tier] = true;
            require(_buyAmounts[i] > 0, "BuyAmounts cannot be 0");
            buyAmount[tier] = _buyAmounts[i];
            isbuyAmountSet[tier] = true;
        }
    }

    function addLevels(uint8 _tiers, uint8[] memory _levels, uint256[] memory _rewards) external onlyOwner {
        require(tiers[_tiers], "Tier does not exist");
        require(_levels.length == _rewards.length, "Invalid rewards length");
        for (uint i = 0; i < _levels.length; i++) {
            uint8 level = _levels[i];
            require(!levels[_tiers][level], "Level already exists");
            require(_rewards[i] > 0, "Rewards cannot be 0");
            levels[_tiers][level] = true;
            levelsPerTier[_tiers] += 1;
            rewards[_tiers][level] = _rewards[i];
            isRewardSet[_tiers][level] = true;
        }
    }

    function removeTier(uint8 _tier) onlyOwner external {
        require(tiers[_tier], "Tier does not exist");
        delete tiers[_tier];
        isbuyAmountSet[_tier] = false;
    }

    function removeLevel(uint8 _tier, uint8 _level) onlyOwner external {
        require(tiers[_tier], "Tier does not exist");
        require(levels[_tier][_level], "Level does not exist");
        delete levels[_tier][_level];
        levelsPerTier[_tier] -= 1;
        delete rewards[_tier][_level];
        isRewardSet[_tier][_level] = false;
    }

    function removeTiers(uint8[] memory _tiers) external onlyOwner {
        for (uint i = 0; i < _tiers.length; i++){
            require(tiers[_tiers[i]], "Tier does not exist");
            delete tiers[_tiers[i]];
            isbuyAmountSet[_tiers[i]] = false;
        }
    }

    function removeLevels(uint8 _tiers, uint8[] memory _levels) external onlyOwner {
        for (uint i = 0; i < _levels.length; i++){
            require(tiers[_tiers], "Tier does not exist");
            require(levels[_tiers][_levels[i]], "Level does not exist");
            delete levels[_tiers][_levels[i]];
            levelsPerTier[_tiers] -= 1;
            delete rewards[_tiers][_levels[i]];
            isRewardSet[_tiers][_levels[i]] = false;
        }
    }

    function setRewards(uint8 _tier, uint8 _level, uint256 _newReward) external onlyOwner returns (uint256) {
        require(tiers[_tier], "Tier does not exists");
        require(levels[_tier][_level], "Level does not exists");
        require(_newReward > 0, "Invalid parameter");
        require(rewards[_tier][_level] != _newReward, "Rewards is same");
        isRewardSet[_tier][_level] = true;
        return rewards[_tier][_level] = _newReward;
    }

    function setBuyAmount(uint256 _tier, uint256 _newBuyAmount) external onlyOwner returns (uint256) {
        require(tiers[_tier], "Tier does not exists");
        require(_newBuyAmount > 0, "Invalid parameter"); 
        require(buyAmount[_tier] != _newBuyAmount, "BuyAmount is same");
        isbuyAmountSet[_tier] = true;
        return buyAmount[_tier] = _newBuyAmount;
    }

    function setTokenAddress(address _newsSowlAddress) external onlyOwner {
        require(_newsSowlAddress != address(0), "Address cannot be 0");
        sowl = IERC20(_newsSowlAddress);
    }

    function setTransferedAddress(address newTransferedAddress) external onlyOwner {
        require(newTransferedAddress != address(0), "Address cannot be 0");
        transferedAddress = newTransferedAddress;
    }

    function withdrawToken(address _recipient, uint256 _amount)
        external
        onlyOwner
        nonReentrant
    {
        require(_recipient != address(0), "Address cannot be 0");
        require(sowl.balanceOf(address(this)) >= _amount, "Insufficient balance");
        SafeERC20.safeTransfer(
            sowl,
            _recipient,
            _amount
        );
    }

    function getRewards(uint8 _tier, uint8 _level) external view returns (uint256) {
        return rewards[_tier][_level];
    }

    function getBuyAmount(uint8 _tier) external view returns (uint256) {
        return buyAmount[_tier];
    }  

    function getLevels(uint8 _tier, uint8 _level) external view returns (bool) {
        return levels[_tier][_level];
    } 

    function getTiers(uint8 _tier) external view returns (bool) {
        return tiers[_tier];
    }   

    function getUserInfo(address _user, uint8 _tier) external view returns (address, uint8, uint8[] memory, uint256, bool) {
        User storage userData = user[_user][_tier];
        require(tiers[_tier], "Tier does not exists");
        require(_user != address(0), "Address cannot be 0");
        return (userData.userAddress, userData.tiersBought, userData.levelsCompleted, userData.rewardsEarned, userData.isUserBoughtTier);
    }

    function recoverSigner(bytes32 hash, bytes memory signature)
        internal
        pure
        returns (address)
    {
        bytes32 messageDigest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
        );
        return ECDSA.recover(messageDigest, signature);
    }
}
