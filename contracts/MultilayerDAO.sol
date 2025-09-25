pragma solidity ^0.8.19;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MultilayerDAO is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction
{
    using ECDSA for bytes32;

    uint256 public constant PERIOD_DURATION = 30 days;
    uint256 public constant RANDOM_PARTICIPANTS_PERCENTAGE = 20;

    struct SignedSeed {
        bytes32 seed;
        uint256 revealedAt;
        address signer;
    }

    mapping(uint256 => SignedSeed) public periodSeeds;
    address public trustedSigner;

    event SeedRevealed(
        uint256 indexed periodIndex,
        bytes32 seed,
        address revealedBy
    );

    constructor(
        IVotes _token,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThreshold,
        address _trustedSigner
    )
        Governor("NonPredictableQuartileDAO")
        GovernorSettings(_votingDelay, _votingPeriod, _proposalThreshold)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4)
    {
        trustedSigner = _trustedSigner;
    }

    // PURE функция для расчета номера периода
    function getPeriodIndex(uint256 timestamp) public pure returns (uint256) {
        return timestamp / PERIOD_DURATION;
    }

    function getCurrentPeriodIndex() public view returns (uint256) {
        return getPeriodIndex(block.timestamp);
    }

    // Функция для установки сида с подписью (газ требуется только один раз за период)
    function revealSeedForPeriod(
        uint256 periodIndex,
        bytes32 seed,
        bytes memory signature
    ) public {
        require(
            periodSeeds[periodIndex].revealedAt == 0,
            "Seed already revealed"
        );

        // Проверяем подпись
        bytes32 messageHash = keccak256(
            abi.encodePacked("QuartileDAO Seed", periodIndex, seed)
        );
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address recoveredSigner = ethSignedMessageHash.recover(signature);

        require(
            recoveredSigner == trustedSigner,
            "Invalid signature from trusted signer"
        );

        periodSeeds[periodIndex] = SignedSeed({
            seed: seed,
            revealedAt: block.timestamp,
            signer: recoveredSigner
        });

        emit SeedRevealed(periodIndex, seed, msg.sender);
    }

    // PURE функция определения роли (БЕЗ ГАЗА после установки сида)
    function getParticipantRole(address account) public view returns (uint8) {
        uint256 periodIndex = getCurrentPeriodIndex();
        SignedSeed memory seedData = periodSeeds[periodIndex];

        require(
            seedData.revealedAt != 0,
            "Seed not revealed for current period"
        );

        bytes32 roleHash = keccak256(
            abi.encodePacked(seedData.seed, account, periodIndex)
        );

        uint256 roleValue = uint256(roleHash) % 100;
        return roleValue < RANDOM_PARTICIPANTS_PERCENTAGE ? 1 : 0;
    }

    // Модифицированные функции с проверкой через PURE функцию
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256) {
        require(
            getParticipantRole(msg.sender) == 1,
            "Not a proposer in current period"
        );
        require(
            token.getVotes(msg.sender) >= proposalThreshold(),
            "Votes below proposal threshold"
        );

        return super.propose(targets, values, calldatas, description);
    }

    function castVote(
        uint256 proposalId,
        uint8 support
    ) public override returns (uint256) {
        require(
            getParticipantRole(msg.sender) == 0,
            "Proposers cannot vote in current period"
        );
        require(token.getVotes(msg.sender) > 0, "No voting power");

        return super.castVote(proposalId, support);
    }

    // Функция для предварительной проверки роли в будущем периоде
    function getFutureRole(
        address account,
        uint256 periodsFromNow
    ) public view returns (uint8) {
        uint256 futurePeriodIndex = getCurrentPeriodIndex() + periodsFromNow;
        SignedSeed memory seedData = periodSeeds[futurePeriodIndex];

        require(
            seedData.revealedAt != 0,
            "Seed not revealed for future period"
        );

        bytes32 roleHash = keccak256(
            abi.encodePacked(seedData.seed, account, futurePeriodIndex)
        );

        uint256 roleValue = uint256(roleHash) % 100;
        return roleValue < RANDOM_PARTICIPANTS_PERCENTAGE ? 1 : 0;
    }

    // Стандартные функции Governor...
    function votingDelay()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function quorum(
        uint256 blockNumber
    )
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor) returns (address) {
        return super._executor();
    }
}
