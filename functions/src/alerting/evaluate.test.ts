import { describe, it, expect } from "vitest";
import { evaluate, type Thresholds, type AlertState } from "./evaluate";

const TH: Thresholds = { minC: 5, maxC: 30, enabled: true };
const COOLDOWN = 15 * 60 * 1000; // 15 min
const T0 = 1_000_000_000_000;

const state = (
  status: AlertState["status"],
  lastNotifiedAt: number | null = null
): AlertState => ({ status, lastNotifiedAt });

describe("evaluate", () => {
  it("normal → high fires a high alert", () => {
    const d = evaluate(31, TH, state("normal"), T0, COOLDOWN);
    expect(d.newStatus).toBe("high");
    expect(d.notify).toEqual({ kind: "high" });
  });

  it("normal → low fires a low alert", () => {
    const d = evaluate(4, TH, state("normal"), T0, COOLDOWN);
    expect(d.newStatus).toBe("low");
    expect(d.notify).toEqual({ kind: "low" });
  });

  it("high → high within cooldown is suppressed", () => {
    const d = evaluate(32, TH, state("high", T0), T0 + 60_000, COOLDOWN);
    expect(d.newStatus).toBe("high");
    expect(d.notify).toBeNull();
  });

  it("high → high after cooldown re-fires", () => {
    const d = evaluate(32, TH, state("high", T0), T0 + COOLDOWN, COOLDOWN);
    expect(d.newStatus).toBe("high");
    expect(d.notify).toEqual({ kind: "high" });
  });

  it("low → high fires immediately (new transition beats cooldown)", () => {
    const d = evaluate(35, TH, state("low", T0), T0 + 1000, COOLDOWN);
    expect(d.newStatus).toBe("high");
    expect(d.notify).toEqual({ kind: "high" });
  });

  it("high → normal fires exactly one 'clear'", () => {
    const d1 = evaluate(20, TH, state("high", T0), T0 + 1000, COOLDOWN);
    expect(d1.newStatus).toBe("normal");
    expect(d1.notify).toEqual({ kind: "clear" });
    // next tick, already normal → silent
    const d2 = evaluate(20, TH, state("normal", T0 + 1000), T0 + 2000, COOLDOWN);
    expect(d2.notify).toBeNull();
  });

  it("normal → normal stays silent", () => {
    const d = evaluate(20, TH, state("normal"), T0, COOLDOWN);
    expect(d.newStatus).toBe("normal");
    expect(d.notify).toBeNull();
  });

  it("disabled thresholds never fire and report normal", () => {
    const disabled: Thresholds = { ...TH, enabled: false };
    const d = evaluate(99, disabled, state("high", T0), T0 + 1000, COOLDOWN);
    expect(d.newStatus).toBe("normal");
    expect(d.notify).toBeNull();
  });

  it("boundary: exactly maxC is normal (strict >)", () => {
    const d = evaluate(30, TH, state("normal"), T0, COOLDOWN);
    expect(d.newStatus).toBe("normal");
    expect(d.notify).toBeNull();
  });

  it("boundary: exactly minC is normal (strict <)", () => {
    const d = evaluate(5, TH, state("normal"), T0, COOLDOWN);
    expect(d.newStatus).toBe("normal");
    expect(d.notify).toBeNull();
  });

  it("first-ever reading above max fires (lastNotifiedAt null)", () => {
    const d = evaluate(40, TH, state("normal", null), T0, COOLDOWN);
    expect(d.notify).toEqual({ kind: "high" });
  });
});
