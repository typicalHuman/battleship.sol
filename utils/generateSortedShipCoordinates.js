import fs from "fs";

const FIELD_SIZE = 10;
const MAX_SHIP_POINTS = 20;

const tree = JSON.parse(fs.readFileSync("./data/output.json"));
const proofs = tree.proofs;
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

const sortedProofs = [];
const coordinateNumbers = [];
const coordinateLiterals = [];

const usedCoordinates = {};

for (let x = 0; x < FIELD_SIZE; x++) {
  for (let y = 0; y < FIELD_SIZE; y++) {
    const coordinateKey = `${x + 1}-${literalNumbers[y]}`;
    if (proofs[coordinateKey].hit && !usedCoordinates[coordinateKey]) {
      // need to verify where ship goes bottom or right
      sortedProofs.push(proofs[coordinateKey].proof);
      coordinateNumbers.push(x + 1);
      coordinateLiterals.push(literalNumbers[y]);
      usedCoordinates[coordinateKey] = true;
      let counter = 0;
      let coordinateKeyRight = null;
      do {
        let nextCoordinateNumber = x + 2 + counter;
        coordinateKeyRight =
          nextCoordinateNumber <= FIELD_SIZE
            ? `${nextCoordinateNumber}-${literalNumbers[y]}`
            : null;
        if (coordinateKeyRight && proofs[coordinateKeyRight].hit) {
          coordinateNumbers.push(nextCoordinateNumber);
          coordinateLiterals.push(literalNumbers[y]);
          usedCoordinates[coordinateKeyRight] = true;
          sortedProofs.push(proofs[coordinateKeyRight].proof);
          counter++;
        }
      } while (coordinateKeyRight && proofs[coordinateKeyRight].hit);

      let coordinateKeyBottom = null;
      counter = 0;
      do {
        let nextLiteral = y + 1 + counter;
        coordinateKeyBottom =
          nextLiteral < FIELD_SIZE
            ? `${x + 1}-${literalNumbers[nextLiteral]}`
            : null;
        if (coordinateKeyBottom && proofs[coordinateKeyBottom].hit) {
          coordinateNumbers.push(x + 1);
          coordinateLiterals.push(literalNumbers[nextLiteral]);
          usedCoordinates[coordinateKeyBottom] = true;
          sortedProofs.push(proofs[coordinateKeyBottom].proof);
          counter++;
        }
      } while (coordinateKeyBottom && proofs[coordinateKeyBottom].hit);
    }
  }
}

if (
  sortedProofs.length != 20 ||
  coordinateNumbers.length != 20 ||
  coordinateLiterals.length != 20
) {
  throw Error("Something went wrong");
}

fs.writeFileSync(
  "./data/output_claim.json",
  JSON.stringify({ sortedProofs, coordinateNumbers, coordinateLiterals })
);
