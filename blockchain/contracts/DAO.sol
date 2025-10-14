import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract DAO is AccessControl {
    using Counters for Counters.Counter;
    Counters.Counter private _proposalIds;

    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER_ROLE");

    // Settings stored in basis points for quorum (10000 = 100%)
    struct Settings {
        uint32 votingPeriodSeconds;
        uint16 quorumBps; // 0..10000
    }

    Settings public settings;
    string public metadata; // optional URI or name

    // Proposal structure
    enum VoteChoice {
        None,
        Yes,
        No,
        Abstain
    }

    struct Proposal {
        uint256 id;
        address proposer;
        uint256 startTimestamp;
        uint256 endTimestamp;
        string metadataURI; // json/markdown describing the proposal (Tally-like)
        uint256 yesCount;
        uint256 noCount;
        uint256 abstainCount;
        bool executed;
    }

    // storage
    mapping(uint256 => Proposal) public proposals;
    uint256[] private proposalFeed; // ordered list of proposal ids
    // mapping proposalId => voter => VoteChoice
    mapping(uint256 => mapping(address => VoteChoice)) public votes;

    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);
    event SettingsUpdated(uint32 votingPeriodSeconds, uint16 quorumBps);
    event ProposalCreated(
        uint256 indexed id,
        address indexed proposer,
        string metadataURI,
        uint256 start,
        uint256 end
    );
    event Voted(
        uint256 indexed proposalId,
        address indexed voter,
        VoteChoice choice
    );
    event ProposalExecuted(uint256 indexed proposalId, bool passed);

    modifier onlyMember() {
        require(hasRole(MEMBER_ROLE, msg.sender), "not member");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "not admin");
        _;
    }

    constructor(
        address admin_,
        address[] memory initialMembers_,
        uint32 votingPeriodSeconds_,
        uint16 quorumBps_,
        string memory metadata_
    ) {
        require(admin_ != address(0), "admin zero");
        require(quorumBps_ <= 10000, "quorum invalid");

        // Setup roles
        _setupRole(DEFAULT_ADMIN_ROLE, admin_);
        _setRoleAdmin(MEMBER_ROLE, DEFAULT_ADMIN_ROLE);

        // set settings
        settings = Settings({
            votingPeriodSeconds: votingPeriodSeconds_ == 0
                ? uint32(3 days)
                : votingPeriodSeconds_, // default 3 days
            quorumBps: quorumBps_ // can be zero
        });

        metadata = metadata_;

        // Add admin as member
        _grantRole(MEMBER_ROLE, admin_);

        // Add initial members
        for (uint256 i = 0; i < initialMembers_.length; i++) {
            address m = initialMembers_[i];
            if (m != address(0) && !hasRole(MEMBER_ROLE, m)) {
                _grantRole(MEMBER_ROLE, m);
                emit MemberAdded(m);
            }
        }

        emit SettingsUpdated(settings.votingPeriodSeconds, settings.quorumBps);
    }

    // ADMIN FUNCTIONS

    /// @notice update voting settings (admin only)
    function updateSettings(
        uint32 votingPeriodSeconds_,
        uint16 quorumBps_
    ) external onlyAdmin {
        require(quorumBps_ <= 10000, "quorum invalid");
        settings.votingPeriodSeconds = votingPeriodSeconds_;
        settings.quorumBps = quorumBps_;
        emit SettingsUpdated(votingPeriodSeconds_, quorumBps_);
    }

    /// @notice add member (admin only)
    function addMember(address member) external onlyAdmin {
        require(member != address(0), "zero");
        require(!hasRole(MEMBER_ROLE, member), "already member");
        _grantRole(MEMBER_ROLE, member);
        emit MemberAdded(member);
    }

    /// @notice remove member (admin only)
    function removeMember(address member) external onlyAdmin {
        require(member != address(0), "zero");
        require(hasRole(MEMBER_ROLE, member), "not member");
        _revokeRole(MEMBER_ROLE, member);
        emit MemberRemoved(member);
    }

    // MEMBER / DAO ACTIONS

    /// @notice create a proposal (members only)
    /// @param metadataURI ipfs:// or other description
    function createProposal(
        string calldata metadataURI
    ) external onlyMember returns (uint256) {
        _proposalIds.increment();
        uint256 pid = _proposalIds.current();

        uint256 start = block.timestamp;
        uint256 end = start + settings.votingPeriodSeconds;

        Proposal storage p = proposals[pid];
        p.id = pid;
        p.proposer = msg.sender;
        p.startTimestamp = start;
        p.endTimestamp = end;
        p.metadataURI = metadataURI;
        p.yesCount = 0;
        p.noCount = 0;
        p.abstainCount = 0;
        p.executed = false;

        proposalFeed.push(pid);

        emit ProposalCreated(pid, msg.sender, metadataURI, start, end);
        return pid;
    }

    /// @notice vote on a proposal (members only). Can change vote while voting period is open.
    function vote(uint256 proposalId, VoteChoice choice) external onlyMember {
        require(
            choice == VoteChoice.Yes ||
                choice == VoteChoice.No ||
                choice == VoteChoice.Abstain,
            "invalid choice"
        );
        Proposal storage p = proposals[proposalId];
        require(p.id != 0, "proposal not found");
        require(block.timestamp >= p.startTimestamp, "not started");
        require(block.timestamp <= p.endTimestamp, "ended");
        VoteChoice prev = votes[proposalId][msg.sender];

        // remove previous vote counts if any
        if (prev == VoteChoice.Yes) {
            p.yesCount -= 1;
        } else if (prev == VoteChoice.No) {
            p.noCount -= 1;
        } else if (prev == VoteChoice.Abstain) {
            p.abstainCount -= 1;
        }

        // set new
        votes[proposalId][msg.sender] = choice;
        if (choice == VoteChoice.Yes) {
            p.yesCount += 1;
        } else if (choice == VoteChoice.No) {
            p.noCount += 1;
        } else if (choice == VoteChoice.Abstain) {
            p.abstainCount += 1;
        }

        emit Voted(proposalId, msg.sender, choice);
    }

    /// @notice execute proposal after voting period. Determines pass/fail by quorum and majority.
    /// Execution here is logical (no onchain actions are predefined). For real governance, extend to call other contracts or emit rich events.
    function executeProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(p.id != 0, "proposal not found");
        require(block.timestamp > p.endTimestamp, "voting not finished");
        require(!p.executed, "already executed");

        p.executed = true;

        bool passed = _proposalPassed(p);
        emit ProposalExecuted(proposalId, passed);

        // For extensibility: if passed, an offchain or onchain mechanism could call arbitrary execution logic.
    }

    // VIEW / HELPERS

    function _proposalPassed(Proposal storage p) internal view returns (bool) {
        uint256 totalMembers = getMemberCount();
        // if no members -> not passed
        if (totalMembers == 0) return false;

        // check quorum: total votes (yes + no + abstain) must be >= quorum% of members
        uint256 totalVotes = p.yesCount + p.noCount + p.abstainCount;

        // quorumBps is basis points (10000 = 100%)
        uint256 requiredQuorum = (uint256(settings.quorumBps) *
            totalMembers +
            9999) / 10000; // ceil
        if (requiredQuorum > 0 && totalVotes < requiredQuorum) {
            return false;
        }

        // majority: yes > no
        if (p.yesCount <= p.noCount) return false;

        return true;
    }

    /// @notice get proposal ids with pagination (offset, limit)
    function getProposals(
        uint256 offset,
        uint256 limit
    ) external view returns (Proposal[] memory) {
        uint256 total = proposalFeed.length;
        if (offset >= total) {
            return new Proposal;
        }
        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 size = end - offset;
        Proposal[] memory out = new Proposal[](size);
        for (uint256 i = 0; i < size; i++) {
            out[i] = proposals[proposalFeed[offset + i]];
        }
        return out;
    }

    function getProposalIds() external view returns (uint256[] memory) {
        return proposalFeed;
    }

    /// @notice get a single proposal and its votes counts
    function getProposal(
        uint256 proposalId
    )
        external
        view
        returns (
            uint256 id,
            address proposer,
            uint256 startTimestamp,
            uint256 endTimestamp,
            string memory metadataURI,
            uint256 yesCount,
            uint256 noCount,
            uint256 abstainCount,
            bool executed
        )
    {
        Proposal storage p = proposals[proposalId];
        require(p.id != 0, "proposal not found");
        return (
            p.id,
            p.proposer,
            p.startTimestamp,
            p.endTimestamp,
            p.metadataURI,
            p.yesCount,
            p.noCount,
            p.abstainCount,
            p.executed
        );
    }

    /// @notice returns number of members (note: AccessControl doesn't expose enumeration; we track roles through events / external indexing or use enumerable extension if needed)
    /// For simplicity here, we count members by scanning proposal of role grants is not possible onchain; therefore we maintain memberCount via internal bookkeeping.
    // To keep on-chain accurate member count we can maintain an internal counter. Implement it below.

    uint256 private _memberCount = 0;
    mapping(address => bool) private _isMemberCached;

    // override grant/revoke role to keep _memberCount accurate when role changes happen only via our functions
    function _grantRole(
        bytes32 role,
        address account
    ) internal virtual override {
        super._grantRole(role, account);
        if (role == MEMBER_ROLE && !_isMemberCached[account]) {
            _isMemberCached[account] = true;
            _memberCount += 1;
        }
    }

    function _revokeRole(
        bytes32 role,
        address account
    ) internal virtual override {
        super._revokeRole(role, account);
        if (role == MEMBER_ROLE && _isMemberCached[account]) {
            _isMemberCached[account] = false;
            if (_memberCount > 0) {
                _memberCount -= 1;
            }
        }
    }

    function getMemberCount() public view returns (uint256) {
        return _memberCount;
    }

    function isMember(address who) external view returns (bool) {
        return hasRole(MEMBER_ROLE, who);
    }

    // -- Utility: allow admin to bootstrap member cache if external grants were used
    function adminSyncMember(
        address who,
        bool isMemberFlag
    ) external onlyAdmin {
        bool has = hasRole(MEMBER_ROLE, who);
        if (has && !isMemberFlag) {
            // admin says remove
            _revokeRole(MEMBER_ROLE, who);
        } else if (!has && isMemberFlag) {
            _grantRole(MEMBER_ROLE, who);
        }
        // if equal, do nothing
    }

    // Fallback: receive ETH (unused but present)
    receive() external payable {}
}
