import { describe, it, expect } from "vitest";
import { accountIdForEmail } from "./id";

describe("accountIdForEmail", () => {
  it("is deterministic for the same email", () => {
    expect(accountIdForEmail("a@b.no")).toBe(accountIdForEmail("a@b.no"));
  });

  it("normalizes case and surrounding whitespace", () => {
    const base = accountIdForEmail("user@example.com");
    expect(accountIdForEmail("USER@Example.com")).toBe(base);
    expect(accountIdForEmail("  user@example.com  ")).toBe(base);
  });

  it("distinguishes different emails", () => {
    expect(accountIdForEmail("a@b.no")).not.toBe(accountIdForEmail("c@d.no"));
  });

  it("produces a hex sha256 (64 chars)", () => {
    expect(accountIdForEmail("a@b.no")).toMatch(/^[0-9a-f]{64}$/);
  });
});
