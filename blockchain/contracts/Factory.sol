// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./DAO.sol";

contract Factory {
    using Counters for Counters.Counter;
    Counters.Counter private _daoCounter;

    event DAOCreated(
        address indexed daoAddress,
        address indexed admin,
        uint256 indexed daoId
    );

    struct DAOInfo {
        address daoAddress;
        address admin;
        string metadata; // optional: URI or name
    }

    mapping(uint256 => DAOInfo) public daos;

    function createDAO(
        address admin_,
        string calldata metadata_,
        address[] calldata initialMembers_,
        uint32 votingPeriodSeconds_, // e.g. 3 days = 259200
        uint16 quorumPercent_ // 0..10000, where 10000 = 100.00% (we'll use basis points)
    ) external returns (address) {
        require(admin_ != address(0), "admin zero");
        require(quorumPercent_ <= 10000, "quorum > 100%");
        _daoCounter.increment();
        uint256 newId = _daoCounter.current();

        DAO dao = new DAO(
            admin_,
            initialMembers_,
            votingPeriodSeconds_,
            quorumPercent_,
            metadata_
        );

        daos[newId] = DAOInfo({
            daoAddress: address(dao),
            admin: admin_,
            metadata: metadata_
        });

        emit DAOCreated(address(dao), admin_, newId);
        return address(dao);
    }

    function totalDAOs() external view returns (uint256) {
        return _daoCounter.current();
    }
}
