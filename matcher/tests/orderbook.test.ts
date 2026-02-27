import { describe, it, expect, beforeEach } from "vitest";
import { OrderBook } from "../src/orderbook.js";
import type { PlaintextOrder } from "../src/types.js";

function makeOrder(overrides: Partial<PlaintextOrder> = {}): PlaintextOrder {
  return {
    commitment: `0x${Math.random().toString(16).slice(2).padStart(64, "0")}` as `0x${string}`,
    price: 100n,
    amount: 10n,
    side: 0,
    salt: BigInt(Math.floor(Math.random() * 1e18)),
    owner: "0x1234567890123456789012345678901234567890",
    tokenPairId: 1,
    timestamp: Date.now(),
    txHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
    ...overrides,
  };
}

describe("OrderBook", () => {
  let book: OrderBook;

  beforeEach(() => {
    book = new OrderBook();
  });

  describe("addOrder", () => {
    it("should add a buy order to the book", () => {
      const order = makeOrder({ side: 0, price: 100n });
      const matches = book.addOrder(order);

      expect(matches).toHaveLength(0);
      expect(book.getBuyOrders(1)).toHaveLength(1);
      expect(book.getOrderCount()).toBe(1);
    });

    it("should add a sell order to the book", () => {
      const order = makeOrder({ side: 1, price: 100n });
      const matches = book.addOrder(order);

      expect(matches).toHaveLength(0);
      expect(book.getSellOrders(1)).toHaveLength(1);
    });

    it("should sort buy orders descending by price", () => {
      book.addOrder(makeOrder({ side: 0, price: 100n }));
      book.addOrder(makeOrder({ side: 0, price: 110n }));
      book.addOrder(makeOrder({ side: 0, price: 105n }));

      const buys = book.getBuyOrders(1);
      expect(buys[0].order.price).toBe(110n);
      expect(buys[1].order.price).toBe(105n);
      expect(buys[2].order.price).toBe(100n);
    });

    it("should sort sell orders ascending by price", () => {
      book.addOrder(makeOrder({ side: 1, price: 100n }));
      book.addOrder(makeOrder({ side: 1, price: 90n }));
      book.addOrder(makeOrder({ side: 1, price: 95n }));

      const sells = book.getSellOrders(1);
      expect(sells[0].order.price).toBe(90n);
      expect(sells[1].order.price).toBe(95n);
      expect(sells[2].order.price).toBe(100n);
    });
  });

  describe("matching", () => {
    it("should match crossing orders", () => {
      book.addOrder(makeOrder({ side: 1, price: 100n, amount: 10n }));
      const matches = book.addOrder(
        makeOrder({ side: 0, price: 100n, amount: 10n })
      );

      expect(matches).toHaveLength(1);
      expect(matches[0].fillAmount).toBe(10n);
      expect(matches[0].settlementPrice).toBe(100n); // midpoint of 100 and 100
    });

    it("should match at midpoint price", () => {
      book.addOrder(makeOrder({ side: 1, price: 98n, amount: 10n }));
      const matches = book.addOrder(
        makeOrder({ side: 0, price: 102n, amount: 10n })
      );

      expect(matches).toHaveLength(1);
      expect(matches[0].settlementPrice).toBe(100n); // (102 + 98) / 2
    });

    it("should not match non-crossing orders", () => {
      book.addOrder(makeOrder({ side: 1, price: 110n, amount: 10n }));
      const matches = book.addOrder(
        makeOrder({ side: 0, price: 100n, amount: 10n })
      );

      expect(matches).toHaveLength(0);
      expect(book.getBuyOrders(1)).toHaveLength(1);
      expect(book.getSellOrders(1)).toHaveLength(1);
    });

    it("should handle partial fills", () => {
      book.addOrder(makeOrder({ side: 1, price: 100n, amount: 20n }));
      const matches = book.addOrder(
        makeOrder({ side: 0, price: 100n, amount: 10n })
      );

      expect(matches).toHaveLength(1);
      expect(matches[0].fillAmount).toBe(10n);
      // Sell order should have remaining amount
      expect(book.getSellOrders(1)).toHaveLength(1);
      expect(book.getSellOrders(1)[0].remainingAmount).toBe(10n);
      // Buy order fully filled, removed from book
      expect(book.getBuyOrders(1)).toHaveLength(0);
    });

    it("should match multiple orders in sequence", () => {
      book.addOrder(makeOrder({ side: 1, price: 100n, amount: 5n }));
      book.addOrder(makeOrder({ side: 1, price: 101n, amount: 5n }));

      const matches = book.addOrder(
        makeOrder({ side: 0, price: 105n, amount: 8n })
      );

      expect(matches).toHaveLength(2);
      expect(matches[0].fillAmount).toBe(5n); // fills 100 ask first
      expect(matches[1].fillAmount).toBe(3n); // partially fills 101 ask
    });

    it("should handle same-pair matching only", () => {
      book.addOrder(
        makeOrder({ side: 1, price: 100n, amount: 10n, tokenPairId: 1 })
      );
      const matches = book.addOrder(
        makeOrder({ side: 0, price: 100n, amount: 10n, tokenPairId: 2 })
      );

      expect(matches).toHaveLength(0);
    });
  });

  describe("removeOrder", () => {
    it("should remove an order from the book", () => {
      const order = makeOrder({ side: 0, price: 100n });
      book.addOrder(order);

      const removed = book.removeOrder(order.commitment);
      expect(removed).toBe(true);
      expect(book.getOrderCount()).toBe(0);
    });

    it("should return false for non-existent order", () => {
      const removed = book.removeOrder("0xnonexistent");
      expect(removed).toBe(false);
    });
  });

  describe("best bid/ask", () => {
    it("should return best bid", () => {
      book.addOrder(makeOrder({ side: 0, price: 100n }));
      book.addOrder(makeOrder({ side: 0, price: 105n }));

      expect(book.getBestBid(1)).toBe(105n);
    });

    it("should return best ask", () => {
      book.addOrder(makeOrder({ side: 1, price: 100n }));
      book.addOrder(makeOrder({ side: 1, price: 95n }));

      expect(book.getBestAsk(1)).toBe(95n);
    });

    it("should return null for empty book", () => {
      expect(book.getBestBid(1)).toBeNull();
      expect(book.getBestAsk(1)).toBeNull();
    });
  });

  describe("pendingMatches", () => {
    it("should track pending matches", () => {
      book.addOrder(makeOrder({ side: 1, price: 100n, amount: 10n }));
      book.addOrder(makeOrder({ side: 0, price: 100n, amount: 10n }));

      const pending = book.getPendingMatches();
      expect(pending).toHaveLength(1);
    });

    it("should clear pending matches", () => {
      book.addOrder(makeOrder({ side: 1, price: 100n, amount: 10n }));
      book.addOrder(makeOrder({ side: 0, price: 100n, amount: 10n }));

      book.clearPendingMatches(1);
      expect(book.getPendingMatches()).toHaveLength(0);
    });
  });
});
