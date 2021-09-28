pragma solidity ^0.5.6;

import "./klaytn-contracts/token/KIP17/IKIP17Enumerable.sol";
import "./klaytn-contracts/ownership/Ownable.sol";
import "./klaytn-contracts/math/SafeMath.sol";
import "./interfaces/IDSCVote.sol";

contract DSCVote is Ownable, IDSCVote {
    using SafeMath for uint256;
    
    uint8 public constant VOTING = 0;
    uint8 public constant CANCELED = 1;
    uint8 public constant RESULT_SAME = 2;
    uint8 public constant RESULT_FOR = 3;
    uint8 public constant RESULT_AGAINST = 4;

    mapping(address => bool) public matesAllowed;
    uint256 public minProposePeriod = 86400;
    uint256 public maxProposePeriod = 604800;
    uint256 public proposeMateCount = 25;

    struct Proposal {
        address proposer;
        string title;
        string summary;
        string content;
        string note;
        uint256 blockNumber;
        address proposeMates;
        uint256 votePeriod;
        bool canceled;
        bool executed;
    }
    Proposal[] public proposals;
    mapping(uint256 => mapping(address => uint256[])) public proposeMates;
    mapping(uint256 => uint256) public forVotes;
    mapping(uint256 => uint256) public againstVotes;
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) public mateVoted;

    function allowMates(address mates) onlyOwner external {
        matesAllowed[mates] = true;
    }

    function disallowMates(address mates) onlyOwner external {
        matesAllowed[mates] = false;
    }

    function setMinProposePeriod(uint256 period) onlyOwner external {
        minProposePeriod = period;
    }

    function setMaxProposePeriod(uint256 period) onlyOwner external {
        maxProposePeriod = period;
    }

    function setProposeMateCount(uint256 count) onlyOwner external {
        proposeMateCount = count;
    }

    function propose(

        string calldata title,
        string calldata summary,
        string calldata content,
        string calldata note,
        uint256 votePeriod,

        address _mates,
        uint256[] calldata mateIds

    ) external returns (uint256 proposalId) {
        require(matesAllowed[_mates] == true);
        require(mateIds.length == proposeMateCount);
        require(minProposePeriod <= votePeriod && votePeriod <= maxProposePeriod);

        proposalId = proposals.length;
        proposals.push(Proposal({
            proposer: msg.sender,
            title: title,
            summary: summary,
            content: content,
            note: note,
            blockNumber: block.number,
            proposeMates: _mates,
            votePeriod: votePeriod,
            canceled: false,
            executed: false
        }));
        
        uint256[] storage proposed = proposeMates[proposalId][_mates];
        IKIP17Enumerable mates = IKIP17Enumerable(_mates);

        for (uint256 index = 0; index < proposeMateCount; index = index.add(1)) {
            uint256 id = mateIds[index];
            require(mates.ownerOf(id) == msg.sender);
            mates.transferFrom(msg.sender, address(this), id);
            proposed.push(id);
        }

        emit Propose(proposalId, msg.sender, _mates, mateIds);
    }
    
    function proposalCount() view external returns (uint256) {
        return proposals.length;
    }

    modifier onlyVoting(uint256 proposalId) {
        Proposal memory proposal = proposals[proposalId];
        require(
            proposal.canceled != true &&
            proposal.executed != true &&
            proposal.blockNumber.add(proposal.votePeriod) >= block.number
        );
        _;
    }
    
    function voteMate(uint256 proposalId, address _mates, uint256[] memory mateIds) internal {
        require(matesAllowed[_mates] == true);
        
        mapping(uint256 => bool) storage voted = mateVoted[proposalId][_mates];
        IKIP17Enumerable mates = IKIP17Enumerable(_mates);

        uint256 length = mateIds.length;
        for (uint256 index = 0; index < length; index = index.add(1)) {
            uint256 id = mateIds[index];
            require(mates.ownerOf(id) == msg.sender && voted[id] != true);
            voted[id] = true;
        }
    }

    function voteFor(uint256 proposalId, address mates, uint256[] calldata mateIds) onlyVoting(proposalId) external {
        voteMate(proposalId, mates, mateIds);
        forVotes[proposalId] = forVotes[proposalId].add(mateIds.length);
        emit VoteFor(proposalId, msg.sender, mates, mateIds);
    }

    function voteAgainst(uint256 proposalId, address mates, uint256[] calldata mateIds) onlyVoting(proposalId) external {
        voteMate(proposalId, mates, mateIds);
        againstVotes[proposalId] = againstVotes[proposalId].add(mateIds.length);
        emit VoteAgainst(proposalId, msg.sender, mates, mateIds);
    }

    modifier onlyProposer(uint256 proposalId) {
        require(proposals[proposalId].proposer == msg.sender);
        _;
    }

    function getBackMates(uint256 proposalId) onlyProposer(proposalId) external {
        require(result(proposalId) != VOTING);

        Proposal memory proposal = proposals[proposalId];
        uint256[] memory proposed = proposeMates[proposalId][proposal.proposeMates];
        IKIP17Enumerable mates = IKIP17Enumerable(proposal.proposeMates);
        uint256 length = proposed.length;

        for (uint256 index = 0; index < length; index = index.add(1)) {
            mates.transferFrom(address(this), proposal.proposer, proposed[index]);
        }

        delete proposeMates[proposalId][proposal.proposeMates];
    }
    
    function matesBacked(uint256 proposalId) view external returns (bool) {
        Proposal memory proposal = proposals[proposalId];
        return proposeMates[proposalId][proposal.proposeMates].length == 0;
    }

    function cancel(uint256 proposalId) onlyProposer(proposalId) external {
        Proposal memory proposal = proposals[proposalId];
        require(proposal.blockNumber.add(proposal.votePeriod) >= block.number);
        proposals[proposalId].canceled = true;
        emit Cancel(proposalId);
    }

    function execute(uint256 proposalId) onlyProposer(proposalId) external {
        require(result(proposalId) == RESULT_FOR);
        proposals[proposalId].executed = true;
        emit Execute(proposalId);
    }

    function result(uint256 proposalId) view public returns (uint8) {
        Proposal memory proposal = proposals[proposalId];
        uint256 _for = forVotes[proposalId];
        uint256 _against = againstVotes[proposalId];
        if (proposal.canceled == true) {
            return CANCELED;
        } else if (proposal.blockNumber.add(proposal.votePeriod) >= block.number) {
            return VOTING;
        } else if (_for == _against) {
            return RESULT_SAME;
        } else if (_for > _against) {
            return RESULT_FOR;
        } else {
            return RESULT_AGAINST;
        }
    }
}
