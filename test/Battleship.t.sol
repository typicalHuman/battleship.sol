// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/Battleship.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract BattleshipTest is Test {
    Battleship battleship;
    MockERC20 token;
    mapping(uint => string) literalNumbers;
    address player1 = address(0x1);
    address player2 = address(0x2);
    address attacker = address(0x3);
    uint256 depositAmount = 1 ether;

    mapping(bytes => bool) markedCoordinates; // for ships detection

    function setUp() public {
        token = new MockERC20();
        battleship = new Battleship(address(token), depositAmount);

        // Fund player accounts
        token.transfer(player1, depositAmount);
        token.transfer(player2, depositAmount);

        vm.prank(player1);
        token.approve(address(battleship), depositAmount);

        vm.prank(player2);
        token.approve(address(battleship), depositAmount);
        literalNumbers[1] = "A";
        literalNumbers[2] = "B";
        literalNumbers[3] = "C";
        literalNumbers[4] = "D";
        literalNumbers[5] = "E";
        literalNumbers[6] = "F";
        literalNumbers[7] = "G";
        literalNumbers[8] = "H";
        literalNumbers[9] = "I";
        literalNumbers[10] = "J";
    }

    function testCreateGame() public {
        vm.prank(player1);
        bytes32 boardRoot = keccak256("boardRootPlayer1");
        uint256 gameId = battleship.createGame(player2, boardRoot);

        (uint256 id, , address p1, address p2, address winner) = battleship
            .games(gameId);

        assertEq(id, 0);
        assertEq(p1, player1);
        assertEq(p2, player2);
        assertEq(winner, address(0));
        assertEq(
            battleship.boardRoots(battleship.playerBoardId(player1, gameId)),
            boardRoot
        );
    }

    function testCancelGame_RevertsIfNotExpired() public {
        vm.prank(player1);
        bytes32 boardRoot = keccak256("boardRootPlayer1");
        uint256 gameId = battleship.createGame(player2, boardRoot);

        vm.expectRevert(Battleship.GameNotExpired.selector);
        vm.prank(player1);
        battleship.cancelGame(gameId);
    }

    function testMakeMove() public {
        vm.prank(player1);
        bytes32 boardRoot = keccak256("boardRootPlayer1");
        uint256 gameId = battleship.createGame(player2, boardRoot);

        vm.prank(player1);
        battleship.makeMove(gameId, 5, "A");

        (
            ,
            address player,
            ,
            ,
            Battleship.Coordinate memory coordinates
        ) = battleship.lastMoves(gameId);
        assertEq(player, player1);
        assertEq(coordinates.coordinateNumber, 5);
        assertEq(coordinates.coordinateLiteral, "A");
    }

    function testMakeMove_RevertsIfInvalidCoordinates() public {
        vm.prank(player1);
        bytes32 boardRoot = keccak256("boardRootPlayer1");
        uint256 gameId = battleship.createGame(player2, boardRoot);

        vm.expectRevert(Battleship.InvalidCoordinates.selector);
        vm.prank(player1);
        battleship.makeMove(gameId, 11, "A");
    }

    function testConfirmMove_Miss() public {
        string memory board1Path = "test/mocks/trees/1.json";
        string memory board2Path = "test/mocks/trees/2.json";
        string memory json1 = vm.readFile(board1Path);
        string memory json2 = vm.readFile(board2Path);

        bytes32 boardRootP1 = vm.parseJsonBytes32(json1, ".root");
        bytes32 boardRootP2 = vm.parseJsonBytes32(json2, ".root");

        vm.prank(player1);
        uint256 gameId = battleship.createGame(player2, boardRootP1);

        vm.prank(player2);
        battleship.setGameBoard(gameId, boardRootP2);

        vm.prank(player1);
        battleship.makeMove(gameId, 5, "A");

        bytes32[] memory proof = abi.decode(
            vm.parseJson(json2, '.proofs["5-A"].proof'),
            (bytes32[])
        );
        bool hit = abi.decode(
            vm.parseJson(json2, '.proofs["5-A"].hit'),
            (bool)
        );

        vm.prank(player2);
        battleship.confirmMove(gameId, proof, hit);

        bytes32 playerBoardId = battleship.playerBoardId(player2, gameId);
        bytes32 coordinatesId = battleship.coordinatesId(
            5,
            battleship.literals("A")
        );

        assertEq(
            uint8(battleship.gameHits(playerBoardId, coordinatesId)),
            uint8(Battleship.Status.NoHit)
        );
        assertEq(
            battleship.gameCorrectHits(playerBoardId, coordinatesId),
            false
        );
    }
    function testConfirmMove_Hit() public {
        string memory board1Path = "test/mocks/trees/1.json";
        string memory board2Path = "test/mocks/trees/2.json";
        string memory json1 = vm.readFile(board1Path);
        string memory json2 = vm.readFile(board2Path);

        bytes32 boardRootP1 = vm.parseJsonBytes32(json1, ".root");
        bytes32 boardRootP2 = vm.parseJsonBytes32(json2, ".root");

        vm.prank(player1);
        uint256 gameId = battleship.createGame(player2, boardRootP1);

        vm.prank(player2);
        battleship.setGameBoard(gameId, boardRootP2);

        vm.prank(player1);
        battleship.makeMove(gameId, 1, "H");

        bytes32[] memory proof = abi.decode(
            vm.parseJson(json2, '.proofs["1-H"].proof'),
            (bytes32[])
        );
        bool hit = abi.decode(
            vm.parseJson(json2, '.proofs["1-H"].hit'),
            (bool)
        );

        vm.prank(player2);
        battleship.confirmMove(gameId, proof, hit);

        bytes32 playerBoardId = battleship.playerBoardId(player2, gameId);
        bytes32 coordinatesId = battleship.coordinatesId(
            1,
            battleship.literals("H")
        );

        assertEq(
            uint8(battleship.gameHits(playerBoardId, coordinatesId)),
            uint8(Battleship.Status.Hit)
        );
        assertEq(
            battleship.gameCorrectHits(playerBoardId, coordinatesId),
            true
        );
    }
    function testWin1() public {
        string memory board1Path = "test/mocks/trees/1.json";
        string memory board2Path = "test/mocks/trees/2.json";
        string memory json1 = vm.readFile(board1Path);
        string memory json2 = vm.readFile(board2Path);

        bytes32 boardRootP1 = vm.parseJsonBytes32(json1, ".root");
        bytes32 boardRootP2 = vm.parseJsonBytes32(json2, ".root");

        vm.prank(player1);
        uint256 gameId = battleship.createGame(player2, boardRootP1);

        vm.prank(player2);
        battleship.setGameBoard(gameId, boardRootP2);
        _winGame(gameId, json2);
        assertEq(battleship.getWinner(gameId), player1);
    }
    function testWin1Reversed() public {
        string memory board1Path = "test/mocks/trees/2.json";
        string memory board2Path = "test/mocks/trees/1.json";
        string memory json1 = vm.readFile(board1Path);
        string memory json2 = vm.readFile(board2Path);

        bytes32 boardRootP1 = vm.parseJsonBytes32(json1, ".root");
        bytes32 boardRootP2 = vm.parseJsonBytes32(json2, ".root");

        vm.prank(player1);
        uint256 gameId = battleship.createGame(player2, boardRootP1);

        vm.prank(player2);
        battleship.setGameBoard(gameId, boardRootP2);
        _winGame(gameId, json2);
        assertEq(battleship.getWinner(gameId), player1);
    }
    function testWin2() public {
        string memory board1Path = "test/mocks/trees/2.json";
        string memory board2Path = "test/mocks/trees/3.json";
        string memory json1 = vm.readFile(board1Path);
        string memory json2 = vm.readFile(board2Path);

        bytes32 boardRootP1 = vm.parseJsonBytes32(json1, ".root");
        bytes32 boardRootP2 = vm.parseJsonBytes32(json2, ".root");

        vm.prank(player1);
        uint256 gameId = battleship.createGame(player2, boardRootP1);

        vm.prank(player2);
        battleship.setGameBoard(gameId, boardRootP2);
        _winGame(gameId, json2);
        assertEq(battleship.getWinner(gameId), player1);
    }
    function testWin2Reversed() public {
        string memory board1Path = "test/mocks/trees/3.json";
        string memory board2Path = "test/mocks/trees/2.json";
        string memory json1 = vm.readFile(board1Path);
        string memory json2 = vm.readFile(board2Path);

        bytes32 boardRootP1 = vm.parseJsonBytes32(json1, ".root");
        bytes32 boardRootP2 = vm.parseJsonBytes32(json2, ".root");

        vm.prank(player1);
        uint256 gameId = battleship.createGame(player2, boardRootP1);

        vm.prank(player2);
        battleship.setGameBoard(gameId, boardRootP2);
        _winGame(gameId, json2);
        assertEq(battleship.getWinner(gameId), player1);
    }

    function testWin1_ClaimDeposits() public {
        string memory board1Path = "test/mocks/trees/1.json";
        string memory board2Path = "test/mocks/trees/2.json";
        string memory json1 = vm.readFile(board1Path);
        string memory json2 = vm.readFile(board2Path);

        bytes32 boardRootP1 = vm.parseJsonBytes32(json1, ".root");
        bytes32 boardRootP2 = vm.parseJsonBytes32(json2, ".root");

        vm.prank(player1);
        uint256 gameId = battleship.createGame(player2, boardRootP1);

        vm.prank(player2);
        battleship.setGameBoard(gameId, boardRootP2);
        _winGame(gameId, json2);
        assertEq(battleship.getWinner(gameId), player1);
        string memory shipsPath1 = "test/mocks/ships/1.json";
        string memory shipsPath2 = "test/mocks/ships/2.json";
        _claim_safe_deposit(gameId, shipsPath1, player1, false);
        _claim_safe_deposit(gameId, shipsPath2, player2, false);
    }
    function testWin1_ClaimDepositsReversed() public {
        string memory board1Path = "test/mocks/trees/2.json";
        string memory board2Path = "test/mocks/trees/1.json";
        string memory json1 = vm.readFile(board1Path);
        string memory json2 = vm.readFile(board2Path);

        bytes32 boardRootP1 = vm.parseJsonBytes32(json1, ".root");
        bytes32 boardRootP2 = vm.parseJsonBytes32(json2, ".root");

        vm.prank(player1);
        uint256 gameId = battleship.createGame(player2, boardRootP1);

        vm.prank(player2);
        battleship.setGameBoard(gameId, boardRootP2);
        _winGame(gameId, json2);
        assertEq(battleship.getWinner(gameId), player1);
        string memory shipsPath1 = "test/mocks/ships/2.json";
        string memory shipsPath2 = "test/mocks/ships/1.json";
        _claim_safe_deposit(gameId, shipsPath1, player1, false);
        _claim_safe_deposit(gameId, shipsPath2, player2, false);
    }
    function testWin2_ClaimDeposits() public {
        string memory board1Path = "test/mocks/trees/1.json";
        string memory board2Path = "test/mocks/trees/3.json";
        string memory json1 = vm.readFile(board1Path);
        string memory json2 = vm.readFile(board2Path);

        bytes32 boardRootP1 = vm.parseJsonBytes32(json1, ".root");
        bytes32 boardRootP2 = vm.parseJsonBytes32(json2, ".root");

        vm.prank(player1);
        uint256 gameId = battleship.createGame(player2, boardRootP1);

        vm.prank(player2);
        battleship.setGameBoard(gameId, boardRootP2);
        _winGame(gameId, json2);
        assertEq(battleship.getWinner(gameId), player1);
        string memory shipsPath1 = "test/mocks/ships/1.json";
        string memory shipsPath2 = "test/mocks/ships/3.json";
        _claim_safe_deposit(gameId, shipsPath1, player1, false);
        _claim_safe_deposit(gameId, shipsPath2, player2, false);
    }
    function testWin2_ClaimDepositsReversed() public {
        string memory board1Path = "test/mocks/trees/3.json";
        string memory board2Path = "test/mocks/trees/1.json";
        string memory json1 = vm.readFile(board1Path);
        string memory json2 = vm.readFile(board2Path);

        bytes32 boardRootP1 = vm.parseJsonBytes32(json1, ".root");
        bytes32 boardRootP2 = vm.parseJsonBytes32(json2, ".root");

        vm.prank(player1);
        uint256 gameId = battleship.createGame(player2, boardRootP1);

        vm.prank(player2);
        battleship.setGameBoard(gameId, boardRootP2);
        _winGame(gameId, json2);
        assertEq(battleship.getWinner(gameId), player1);
        string memory shipsPath1 = "test/mocks/ships/3.json";
        string memory shipsPath2 = "test/mocks/ships/1.json";
        _claim_safe_deposit(gameId, shipsPath1, player1, false);
        _claim_safe_deposit(gameId, shipsPath2, player2, false);
    }

    function testIncorrectBoard_Neighbours() public {
        string memory board1Path = "test/mocks/trees/neighboursError.json";
        string memory board2Path = "test/mocks/trees/1.json";
        string memory json1 = vm.readFile(board1Path);
        string memory json2 = vm.readFile(board2Path);

        bytes32 boardRootP1 = vm.parseJsonBytes32(json1, ".root");
        bytes32 boardRootP2 = vm.parseJsonBytes32(json2, ".root");

        vm.prank(player1);
        uint256 gameId = battleship.createGame(player2, boardRootP1);

        vm.prank(player2);
        battleship.setGameBoard(gameId, boardRootP2);
        _winGame(gameId, json2);
        assertEq(battleship.getWinner(gameId), player1);
        string memory shipsPath1 = "test/mocks/ships/neighboursError.json";
        string memory shipsPath2 = "test/mocks/ships/1.json";

        _claim_safe_deposit(gameId, shipsPath1, player1, true);

        _claim_safe_deposit(gameId, shipsPath2, player2, false);
    }
    function testIncorrectBoard_Ships() public {
        string memory board1Path = "test/mocks/trees/shipsError.json";
        string memory board2Path = "test/mocks/trees/1.json";
        string memory json1 = vm.readFile(board1Path);
        string memory json2 = vm.readFile(board2Path);

        bytes32 boardRootP1 = vm.parseJsonBytes32(json1, ".root");
        bytes32 boardRootP2 = vm.parseJsonBytes32(json2, ".root");

        vm.prank(player1);
        uint256 gameId = battleship.createGame(player2, boardRootP1);

        vm.prank(player2);
        battleship.setGameBoard(gameId, boardRootP2);
        _winGame(gameId, json2);
        assertEq(battleship.getWinner(gameId), player1);
        string memory shipsPath1 = "test/mocks/ships/shipsError.json";
        string memory shipsPath2 = "test/mocks/ships/1.json";

        _claim_safe_deposit(gameId, shipsPath1, player1, true);

        _claim_safe_deposit(gameId, shipsPath2, player2, false);
    }

    function _claim_safe_deposit(
        uint gameId,
        string memory shipsPath,
        address player,
        bool expectRevert
    ) internal {
        string memory ship_json = vm.readFile(shipsPath);

        bytes32[][] memory sortedProofs = abi.decode(
            vm.parseJson(ship_json, ".sortedProofs"),
            (bytes32[][])
        );
        uint[] memory coordinateNumbers = abi.decode(
            vm.parseJson(ship_json, ".coordinateNumbers"),
            (uint[])
        );
        string[] memory coordinateLiterals = abi.decode(
            vm.parseJson(ship_json, ".coordinateLiterals"),
            (string[])
        );
        uint balanceBefore = token.balanceOf(player);
        vm.prank(player);
        if (expectRevert) vm.expectRevert();
        battleship.claimSafeDeposit(
            gameId,
            sortedProofs,
            coordinateNumbers,
            coordinateLiterals
        );
        uint balanceAfter = token.balanceOf(player);
        if (expectRevert) vm.expectRevert();
        vm.assertEq(balanceAfter - balanceBefore, depositAmount);
    }

    function _winGame(uint gameId, string memory json) internal {
        for (uint y = 1; y < 11; y++) {
            for (uint x = 1; x < 11; x++) {
                string memory key = _combineStrings(
                    '.proofs["',
                    string(
                        abi.encodePacked(
                            Strings.toString(x),
                            "-",
                            literalNumbers[y]
                        )
                    ),
                    '"].'
                );
                bool hit = abi.decode(
                    vm.parseJson(json, string(abi.encodePacked(key, "hit"))),
                    (bool)
                );
                if (hit) {
                    vm.prank(player1);
                    battleship.makeMove(gameId, x, literalNumbers[y]);

                    bytes32[] memory proof = abi.decode(
                        vm.parseJson(
                            json,
                            string(abi.encodePacked(key, "proof"))
                        ),
                        (bytes32[])
                    );

                    vm.prank(player2);
                    battleship.confirmMove(gameId, proof, hit);
                }
            }
        }
    }

    function _combineStrings(
        string memory str1,
        string memory str2,
        string memory str3
    ) public pure returns (string memory) {
        return string(abi.encodePacked(str1, str2, str3));
    }
}
