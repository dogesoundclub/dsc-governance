pragma solidity ^0.5.6;

import "./klaytn-contracts/ownership/Ownable.sol";
import "./klaytn-contracts/math/SafeMath.sol";
import "./interfaces/IDSCGovernance.sol";

contract DSCGovernance is Ownable, IDSCGovernance {
    using SafeMath for uint256;

    mapping(address => bool) public matesAllowed;

    function allowMates(address mates) onlyOwner external {
        matesAllowed[mates] = true;
    }

    function disallowMates(address mates) onlyOwner external {
        matesAllowed[mates] = false;
    }
    
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) public mateVoted;
}
