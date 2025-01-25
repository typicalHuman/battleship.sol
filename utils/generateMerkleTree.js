import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import fs from "fs";

const FIELD_SIZE = 10;
const MAX_SHIP_POINTS = 20;

const coordinates = JSON.parse(fs.readFileSync("./data/input.json"));

let shipCounter = 0;

const values = [];
const literalNumbers = {
  0: "A",
  1: "B",
  2: "C",
  3: "D",
  4: "E",
  5: "F",
  6: "G",
  7: "H",
  8: "I",
  9: "J",
};
for (let x = 0; x < FIELD_SIZE; x++) {
  for (let y = 0; y < FIELD_SIZE; y++) {
    if (coordinates[y][x]) {
      shipCounter++;
    }
    values.push([coordinates[y][x] == 1, y + 1, literalNumbers[x]]);
  }
}

if (shipCounter != MAX_SHIP_POINTS) {
  throw new Error("You should set 20 coordinates as ship points");
}

const tree = StandardMerkleTree.of(values, ["bool", "uint256", "string"]);

const proofs = {};
for (const [i, v] of tree.entries()) {
  const proof = tree.getProof(i);
  proofs[`${v[1]}-${v[2]}`] = { hit: v[0], proof };
}
console.log("Board Root:", tree.root);

fs.writeFileSync(
  "./data/output.json",
  JSON.stringify({ root: tree.root, proofs })
);
