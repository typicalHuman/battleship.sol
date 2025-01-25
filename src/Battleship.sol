//  _           _   _   _           _     _                  _
// | |         | | | | | |         | |   (_)                | |
// | |__   __ _| |_| |_| | ___  ___| |__  _ _ __   ___  ___ | |
// | '_ \ / _` | __| __| |/ _ \/ __| '_ \| | '_ \ / __|/ _ \| |
// | |_) | (_| | |_| |_| |  __/\__ \ | | | | |_) |\__ \ (_) | |
// |_.__/ \__,_|\__|\__|_|\___||___/_| |_|_| .__(_)___/\___/|_|
//                                        | |
//                                        |_|

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {console} from "forge-std/console.sol";

/// @title Battleship game
/// @author typicalHuman
contract Battleship {
    using SafeERC20 for IERC20;

    ////////////////////////////////////////////////////////////////
    //                           Types                            //
    ////////////////////////////////////////////////////////////////

    enum Status {
        None,
        NoHit,
        Hit
    }

    struct Coordinate {
        uint coordinateNumber;
        string coordinateLiteral;
    }

    struct Move {
        uint timestamp;
        address player;
        bool confirmed; // if other player confirmed what was the actual move
        bool isHit;
        Coordinate coordinates;
    }

    struct Game {
        uint id;
        uint creationTimestamp;
        address player1;
        address player2;
        address winner;
        bool cancelled;
        bool withdrawUnlocked;
    }

    ////////////////////////////////////////////////////////////////
    //                      State Variables                       //
    ////////////////////////////////////////////////////////////////

    uint public gameIdCounter;
    mapping(uint gameId => Game) public games;
    mapping(bytes32 playerBoardId => mapping(bytes32 coordinatesId => Status))
        public gameHits;
    mapping(bytes32 playerBoardId => mapping(bytes32 coordinatesId => bool))
        public gameCorrectHits;
    mapping(bytes32 playerBoardId => uint) public gameCorrectHitsAmount;
    mapping(bytes32 playerBoardId => mapping(uint shipSize => uint))
        public boardShips;
    mapping(bytes32 playerBoardId => bytes32) public boardRoots;
    mapping(bytes32 playerBoardId => bool) public depositClaimed;
    mapping(uint gameId => Move) public lastMoves;
    mapping(string => uint) public literals;

    //////////////////////////////////////////////////////////////
    //                       CONSTANTS                          //
    //////////////////////////////////////////////////////////////

    IERC20 public immutable safeDepositToken;
    uint public immutable safeDeposit;

    uint public constant MAX_HITS_AMOUNT = 20;
    uint public constant GAME_PREPARE_TIME = 1 days;
    uint public constant MOVE_MAX_TIME = 10 minutes;
    uint public constant FIELD_SIZE = 10;

    ////////////////////////////////////////////////////////////////
    //                           Events                           //
    ////////////////////////////////////////////////////////////////

    event GameCreated(uint gameId, address player1, address player2);
    event GameStarted(uint gameId);
    event GameCancelled(uint gameId, address by);
    event NewMove(
        uint gameId,
        uint coordinateNumber,
        string coordinateLiteral,
        address player
    );
    event MoveConfirmed(
        uint gameId,
        uint coordinateNumber,
        string coordinateLiteral,
        bool hit
    );
    event GameWon(uint gameId, address player);
    event SafeDepositClaimed(uint gameId, address player);

    ////////////////////////////////////////////////////////////////
    //                           Errors                           //
    ////////////////////////////////////////////////////////////////

    error InvalidProofsCount(uint numberProvided);
    error ZeroValue();
    error InvalidBoardRoot();
    error IncorrectPlayer();
    error PlayersAreTheSame();
    error PlayerCantCancelGame();
    error GameFinished();
    error GameNotFinished();
    error GameExpired();
    error GameNotExpired();
    error BoardAlreadySet();
    error LastMoveNotConfirmed();
    error InvalidProof();
    error InvalidBoard();
    error InvalidLength();
    error InvalidCoordinates();
    error MoveAlreadyPlayed();
    error CoordinatesNotSorted();

    ////////////////////////////////////////////////////////////////
    //                         Modifiers                          //
    ////////////////////////////////////////////////////////////////

    function _checkCoordinates(
        uint coordinateNumber,
        string memory coordinateLiteral
    ) internal view {
        if (
            coordinateNumber > FIELD_SIZE ||
            coordinateNumber == 0 ||
            literals[coordinateLiteral] == 0
        ) revert InvalidCoordinates();
    }

    function _checkSenderPermission(uint gameId) internal view {
        Game memory game = games[gameId];
        Move memory lastMove = lastMoves[gameId];
        bool wasHit = lastMove.isHit;
        address expectedPlayer = game.player1;
        if (wasHit) {
            expectedPlayer = lastMove.player;
        } else if (lastMove.player != address(0)) {
            expectedPlayer = game.player1 == lastMove.player
                ? game.player2
                : game.player1;
        }
        if (msg.sender != expectedPlayer) revert IncorrectPlayer();
    }
    function _checkGameLiveness(uint gameId) internal view {
        _checkGameNotFinished(gameId);
        _checkGameNotExpired(gameId);
    }

    function _checkGameFinished(uint gameId) internal view {
        if (games[gameId].winner == address(0)) revert GameNotFinished();
    }

    function _checkGameNotFinished(uint gameId) internal view {
        if (games[gameId].winner != address(0)) revert GameFinished();
    }
    function _checkGameNotExpired(uint gameId) internal view {
        if (_isGameExpired(gameId)) revert GameExpired();
    }

    function _isGameExpired(uint gameId) internal view returns (bool) {
        Move memory lastMove = lastMoves[gameId];
        return
            games[gameId].winner != address(0) &&
            (block.timestamp > games[gameId].creationTimestamp ||
                (lastMove.timestamp != 0 &&
                    block.timestamp - lastMove.timestamp > MOVE_MAX_TIME));
    }

    ////////////////////////////////////////////////////////////////
    //                        Constructor                         //
    ////////////////////////////////////////////////////////////////

    constructor(address _safeDepositToken, uint _safeDeposit) {
        if (_safeDepositToken == address(0) || _safeDeposit == 0) {
            revert ZeroValue();
        }
        literals["A"] = 1;
        literals["B"] = 2;
        literals["C"] = 3;
        literals["D"] = 4;
        literals["E"] = 5;
        literals["F"] = 6;
        literals["G"] = 7;
        literals["H"] = 8;
        literals["I"] = 9;
        literals["J"] = 10;
        safeDeposit = _safeDeposit;
        safeDepositToken = IERC20(_safeDepositToken);
    }

    ////////////////////////////////////////////////////////////////
    //                     External functions                     //
    ////////////////////////////////////////////////////////////////

    function createGame(
        address opponent,
        bytes32 boardRoot
    ) external returns (uint) {
        if (opponent == address(0) || boardRoot == bytes32(0))
            revert ZeroValue();
        if (msg.sender == opponent) revert PlayersAreTheSame();
        uint newId = gameIdCounter++;
        games[newId] = Game({
            id: newId,
            creationTimestamp: block.timestamp,
            player1: msg.sender,
            player2: opponent,
            winner: address(0),
            cancelled: false,
            withdrawUnlocked: false
        });
        boardRoots[playerBoardId(msg.sender, newId)] = boardRoot;
        IERC20(safeDepositToken).safeTransferFrom(
            msg.sender,
            address(this),
            safeDeposit
        );

        emit GameCreated(newId, msg.sender, opponent);
        return newId;
    }
    // @audit check if we can withdraw funds if user didn't agree to play
    function cancelGame(uint gameId) external {
        _checkGameNotFinished(gameId);

        if (!_isGameExpired(gameId)) {
            revert GameNotExpired();
        }

        bytes32 playerRoot = boardRoots[playerBoardId(msg.sender, gameId)];

        if (playerRoot == bytes32(0)) {
            revert IncorrectPlayer();
        }
        Move memory lastMove = lastMoves[gameId];
        if (msg.sender != lastMove.player) {
            revert PlayerCantCancelGame();
        }
        games[gameId].winner = msg.sender;
        games[gameId].withdrawUnlocked = true;
        games[gameId].cancelled = true;
        emit GameCancelled(gameId, msg.sender);
    }

    // verify permissions here
    function setGameBoard(uint gameId, bytes32 boardRoot) external {
        _checkGameNotExpired(gameId);
        address player2 = games[gameId].player2;
        if (player2 != msg.sender) revert IncorrectPlayer();
        if (boardRoot == bytes32(0)) revert InvalidBoardRoot();
        if (boardRoots[playerBoardId(msg.sender, gameId)] != bytes32(0))
            revert BoardAlreadySet();
        boardRoots[playerBoardId(msg.sender, gameId)] = boardRoot;
        IERC20(safeDepositToken).safeTransferFrom(
            msg.sender,
            address(this),
            safeDeposit
        );
        emit GameStarted(gameId);
    }

    function makeMove(
        uint gameId,
        uint coordinateNumber,
        string memory coordinateLiteral
    ) external {
        _checkGameLiveness(gameId);
        _checkSenderPermission(gameId);
        _checkCoordinates(coordinateNumber, coordinateLiteral);
        Move memory lastMove = lastMoves[gameId];
        if (lastMove.timestamp > 0 && !lastMove.confirmed) {
            revert LastMoveNotConfirmed();
        }
        if (
            gameHits[playerBoardId(msg.sender, gameId)][
                coordinatesId(coordinateNumber, literals[coordinateLiteral])
            ] != Status.None
        ) {
            revert MoveAlreadyPlayed();
        }
        lastMoves[gameId] = Move({
            player: msg.sender,
            confirmed: false,
            isHit: false,
            timestamp: block.timestamp,
            coordinates: Coordinate({
                coordinateNumber: coordinateNumber,
                coordinateLiteral: coordinateLiteral
            })
        });
        emit NewMove(gameId, coordinateNumber, coordinateLiteral, msg.sender);
    }

    function confirmMove(
        uint gameId,
        bytes32[] calldata _merkleProof,
        bool isCorrectHit
    ) external {
        _checkGameLiveness(gameId);
        Move memory move = lastMoves[gameId];
        Game memory game = games[gameId];
        address expectedAddress = move.player == game.player1
            ? game.player2
            : game.player1;
        if (msg.sender != expectedAddress) revert IncorrectPlayer();
        bytes32 _merkleRoot = boardRoots[
            playerBoardId(expectedAddress, gameId)
        ];
        bytes32 leaf = keccak256(
            abi.encodePacked(
                keccak256(
                    abi.encode(
                        isCorrectHit,
                        move.coordinates.coordinateNumber,
                        move.coordinates.coordinateLiteral
                    )
                )
            )
        );

        if (!MerkleProof.verify(_merkleProof, _merkleRoot, leaf))
            revert InvalidProof();
        bytes32 _playerBoardId = playerBoardId(msg.sender, gameId);
        bytes32 _coordinatesId = coordinatesId(
            move.coordinates.coordinateNumber,
            literals[move.coordinates.coordinateLiteral]
        );
        gameHits[_playerBoardId][_coordinatesId] = isCorrectHit
            ? Status.Hit
            : Status.NoHit;
        if (isCorrectHit) {
            uint totalHits = ++gameCorrectHitsAmount[_playerBoardId];
            gameCorrectHits[_playerBoardId][_coordinatesId] = true;
            if (totalHits == MAX_HITS_AMOUNT) {
                games[gameId].winner = move.player;
                games[gameId].withdrawUnlocked = true;
                emit GameWon(gameId, move.player);
            }
        }
        lastMoves[gameId].confirmed = true;
        lastMoves[gameId].isHit = isCorrectHit;
        emit MoveConfirmed(
            gameId,
            move.coordinates.coordinateNumber,
            move.coordinates.coordinateLiteral,
            isCorrectHit
        );
    }

    function claimSafeDeposit(
        uint gameId,
        bytes32[][] calldata _merkleProofs,
        uint[] memory coordinateNumbers,
        string[] memory coordinateLiterals
    ) external {
        _checkGameFinished(gameId);

        bytes32 _playerBoardId = playerBoardId(msg.sender, gameId);
        bytes32 playerRoot = boardRoots[_playerBoardId];

        if (playerRoot == bytes32(0)) {
            revert IncorrectPlayer();
        }
        bool boardCorrect = _confirmBoardCorrectness(
            gameId,
            _merkleProofs,
            coordinateNumbers,
            coordinateLiterals
        );
        if (boardCorrect && !depositClaimed[_playerBoardId]) {
            IERC20(safeDepositToken).safeTransfer(msg.sender, safeDeposit);
            depositClaimed[_playerBoardId] = true;
        } else {
            revert InvalidBoard();
        }
        emit SafeDepositClaimed(gameId, msg.sender);
    }

    ////////////////////////////////////////////////////////////////
    //                     Internal functions                     //
    ////////////////////////////////////////////////////////////////

    function _confirmBoardCorrectness(
        uint gameId,
        bytes32[][] calldata _merkleProofs,
        uint[] memory coordinateNumbers,
        string[] memory coordinateLiterals
    ) internal returns (bool) {
        if (
            _merkleProofs.length != MAX_HITS_AMOUNT ||
            coordinateLiterals.length != MAX_HITS_AMOUNT ||
            coordinateNumbers.length != MAX_HITS_AMOUNT
        ) {
            revert InvalidLength();
        }
        bytes32 boardId = playerBoardId(msg.sender, gameId);
        uint hitsToVerify = gameCorrectHitsAmount[boardId];

        bytes32 _merkleRoot = boardRoots[boardId];
        uint verifiedHits = _checkShipsPositions(
            _merkleProofs,
            coordinateNumbers,
            coordinateLiterals,
            _merkleRoot,
            boardId
        );
        if (hitsToVerify != verifiedHits) {
            return false;
        }
        return true;
    }

    function _checkShipsPositions(
        bytes32[][] calldata _merkleProofs,
        uint[] memory coordinateNumbers,
        string[] memory coordinateLiterals,
        bytes32 _merkleRoot,
        bytes32 boardId
    ) internal returns (uint verifiedHits) {
        uint previousCoordinateMultiplier = 0;
        uint shipSize = 0;
        bytes32[] memory hitIds = new bytes32[](MAX_HITS_AMOUNT);
        for (uint i = 0; i < MAX_HITS_AMOUNT; i++) {
            uint coordinateNumber = coordinateNumbers[i];
            uint coordinateLiteralNumber = literals[coordinateLiterals[i]];

            uint currentCoordinateMultiplier = (coordinateLiteralNumber *
                FIELD_SIZE) + coordinateNumber;
            if (
                currentCoordinateMultiplier !=
                previousCoordinateMultiplier + 1 &&
                currentCoordinateMultiplier !=
                previousCoordinateMultiplier + FIELD_SIZE
            ) {
                // new ship
                boardShips[boardId][shipSize]++;
                shipSize = 0;
            }
            previousCoordinateMultiplier = currentCoordinateMultiplier;
            shipSize++;
            bytes32 leaf = keccak256(
                abi.encodePacked(
                    keccak256(
                        abi.encode(
                            true,
                            coordinateNumber,
                            coordinateLiterals[i]
                        )
                    )
                )
            );
            if (!MerkleProof.verify(_merkleProofs[i], _merkleRoot, leaf)) {
                return type(uint256).max;
            }
            bytes32 _coordinatesId = coordinatesId(
                coordinateNumber,
                coordinateLiteralNumber
            );
            Status userShot = gameHits[boardId][_coordinatesId];
            if (userShot == Status.Hit) {
                verifiedHits++;
            } else if (userShot == Status.NoHit) {
                return type(uint256).max;
            }

            if (
                !_checkNeighboursIntersections(
                    coordinateNumber,
                    coordinateLiteralNumber,
                    hitIds,
                    i + 1
                )
            ) {
                return type(uint256).max;
            }
            hitIds[i] = _coordinatesId;
        }
        if (shipSize > 0) {
            boardShips[boardId][shipSize]++;
        }
        // check if all correct ships are on board
        if (!_checkCorrectShips(boardId)) {
            return type(uint256).max;
        }
    }

    ////////////////////////////////////////////////////////////////
    //                       View functions                       //
    ////////////////////////////////////////////////////////////////

    function _checkCorrectShips(bytes32 boardId) internal view returns (bool) {
        return (boardShips[boardId][4] == 1 &&
            boardShips[boardId][3] == 2 &&
            boardShips[boardId][2] == 3 &&
            boardShips[boardId][1] == 4);
    }

    function getWinner(uint gameId) external view returns (address) {
        return games[gameId].winner;
    }

    ////////////////////////////////////////////////////////////////
    //                       Pure functions                       //
    ////////////////////////////////////////////////////////////////

    function playerBoardId(
        address player,
        uint gameId
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(player, gameId));
    }

    function coordinatesId(
        uint coordinateNumber,
        uint coordinateLiteralNumber
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(coordinateNumber, coordinateLiteralNumber)
            );
    }
    
    function _checkNeighboursIntersections(
        uint coordinateNumber,
        uint coordinateLiteralNumber,
        bytes32[] memory ids,
        uint idsLength
    ) internal pure returns (bool) {
        uint neighbourCounter = 0;
        for (int i = -1; i < 2; i++) {
            for (int j = -1; j < 2; j++) {
                if (i != 0 || j != 0) {
                    if (
                        _idExists(
                            ids,
                            idsLength,
                            coordinatesId(
                                uint(int(coordinateNumber) + i),
                                uint(int(coordinateLiteralNumber) + j)
                            )
                        )
                    ) {
                        neighbourCounter++;
                    }
                }
            }
        }
        return neighbourCounter <= 1;
    }

    function _idExists(
        bytes32[] memory ids,
        uint idsLength,
        bytes32 idToCheck
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < idsLength; i++) {
            if (ids[i] == idToCheck) {
                return true;
            }
        }
        return false;
    }

}
