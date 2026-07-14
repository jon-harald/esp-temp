import { describe, it, expect } from "vitest";
import { dedupeTokens, chunk, type TokenRef } from "./tokens";

describe("dedupeTokens", () => {
  it("keeps each token once with the first owning uid", () => {
    const refs: TokenRef[] = [
      { token: "t1", uid: "u1" },
      { token: "t2", uid: "u1" },
      { token: "t1", uid: "u2" }, // same physical token under a 2nd login
      { token: "t3", uid: "u2" },
    ];
    const { tokens, owner } = dedupeTokens(refs);
    expect(tokens.sort()).toEqual(["t1", "t2", "t3"]);
    expect(owner.get("t1")).toBe("u1"); // first-writer-wins
    expect(owner.get("t3")).toBe("u2");
  });

  it("handles an empty input", () => {
    const { tokens, owner } = dedupeTokens([]);
    expect(tokens).toEqual([]);
    expect(owner.size).toBe(0);
  });
});

describe("chunk", () => {
  it("splits into fixed-size batches", () => {
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
  });

  it("returns a single batch when under the limit", () => {
    expect(chunk([1, 2, 3], 500)).toEqual([[1, 2, 3]]);
  });

  it("returns nothing for an empty list", () => {
    expect(chunk([], 500)).toEqual([]);
  });
});
