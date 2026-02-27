// ============================================================
// DarkBook Matcher — In-Memory Orderbook
// ============================================================
// Maintains sorted buy/sell orders per trading pair using
// price-time priority. Performs continuous matching when
// crossing orders are detected.

import type { OrderBookEntry, PlaintextOrder, Match, Side } from "./types.js";

export class OrderBook {
  /** Buy orders per pair: sorted descending by price, then ascending by timestamp */
  private buyOrders: Map<number, OrderBookEntry[]> = new Map();

  /** Sell orders per pair: sorted ascending by price, then ascending by timestamp */
  private sellOrders: Map<number, OrderBookEntry[]> = new Map();

  /** All orders indexed by commitment hash */
  private orderIndex: Map<string, OrderBookEntry> = new Map();

  /** Pending matches waiting to be settled */
  private pendingMatches: Match[] = [];

  /**
   * Add a new order to the book
   * Returns any immediate matches (crossing orders)
   */
  addOrder(order: PlaintextOrder): Match[] {
    const entry: OrderBookEntry = {
      order,
      remainingAmount: order.amount,
      isMatched: false,
    };

    // Store in index
    this.orderIndex.set(order.commitment, entry);

    // Try to match against opposite side
    const matches = this.tryMatch(entry);

    // If not fully filled, add remainder to book
    if (entry.remainingAmount > 0n && !entry.isMatched) {
      this.insertIntoBook(entry);
    }

    return matches;
  }

  /**
   * Remove an order from the book (cancellation)
   */
  removeOrder(commitment: string): boolean {
    const entry = this.orderIndex.get(commitment);
    if (!entry) return false;

    const pairId = entry.order.tokenPairId;
    const book =
      entry.order.side === 0
        ? this.buyOrders.get(pairId)
        : this.sellOrders.get(pairId);

    if (book) {
      const idx = book.findIndex(
        (e) => e.order.commitment === commitment
      );
      if (idx !== -1) {
        book.splice(idx, 1);
      }
    }

    this.orderIndex.delete(commitment);
    return true;
  }

  /**
   * Get the best bid (highest buy price) for a pair
   */
  getBestBid(tokenPairId: number): bigint | null {
    const buys = this.buyOrders.get(tokenPairId);
    if (!buys || buys.length === 0) return null;
    return buys[0].order.price;
  }

  /**
   * Get the best ask (lowest sell price) for a pair
   */
  getBestAsk(tokenPairId: number): bigint | null {
    const sells = this.sellOrders.get(tokenPairId);
    if (!sells || sells.length === 0) return null;
    return sells[0].order.price;
  }

  /**
   * Get pending matches for settlement
   */
  getPendingMatches(): Match[] {
    return [...this.pendingMatches];
  }

  /**
   * Clear pending matches after settlement
   */
  clearPendingMatches(count: number): void {
    this.pendingMatches.splice(0, count);
  }

  /**
   * Get order by commitment
   */
  getOrder(commitment: string): OrderBookEntry | undefined {
    return this.orderIndex.get(commitment);
  }

  /**
   * Get all active buy orders for a pair (for debugging/display)
   */
  getBuyOrders(tokenPairId: number): OrderBookEntry[] {
    return [...(this.buyOrders.get(tokenPairId) || [])];
  }

  /**
   * Get all active sell orders for a pair
   */
  getSellOrders(tokenPairId: number): OrderBookEntry[] {
    return [...(this.sellOrders.get(tokenPairId) || [])];
  }

  /**
   * Get the total number of active orders
   */
  getOrderCount(): number {
    return this.orderIndex.size;
  }

  // ============================================================
  //                    PRIVATE METHODS
  // ============================================================

  /**
   * Attempt to match an incoming order against the opposite side
   */
  private tryMatch(incoming: OrderBookEntry): Match[] {
    const matches: Match[] = [];
    const pairId = incoming.order.tokenPairId;

    // Get opposite side book
    const oppositeBook =
      incoming.order.side === 0
        ? this.sellOrders.get(pairId)
        : this.buyOrders.get(pairId);

    if (!oppositeBook || oppositeBook.length === 0) return matches;

    // Iterate through opposite side looking for crosses
    let i = 0;
    while (i < oppositeBook.length && incoming.remainingAmount > 0n) {
      const resting = oppositeBook[i];

      // Check if prices cross
      const pricesCross =
        incoming.order.side === 0
          ? incoming.order.price >= resting.order.price // buyer's limit >= seller's ask
          : incoming.order.price <= resting.order.price; // seller's ask <= buyer's bid

      if (!pricesCross) break; // no more crosses (books are sorted)

      // Compute fill
      const fillAmount =
        incoming.remainingAmount < resting.remainingAmount
          ? incoming.remainingAmount
          : resting.remainingAmount;

      // Settlement price = midpoint
      const settlementPrice =
        (incoming.order.price + resting.order.price) / 2n;

      // Determine buy/sell sides
      const buyOrder =
        incoming.order.side === 0 ? incoming : resting;
      const sellOrder =
        incoming.order.side === 1 ? incoming : resting;

      const match: Match = {
        buyOrder,
        sellOrder,
        fillAmount,
        settlementPrice,
        timestamp: Date.now(),
      };

      matches.push(match);
      this.pendingMatches.push(match);

      // Update remaining amounts
      incoming.remainingAmount -= fillAmount;
      resting.remainingAmount -= fillAmount;

      // Remove fully filled resting order
      if (resting.remainingAmount === 0n) {
        resting.isMatched = true;
        oppositeBook.splice(i, 1);
        this.orderIndex.delete(resting.order.commitment);
      } else {
        i++;
      }
    }

    // Mark incoming as fully matched if no remainder
    if (incoming.remainingAmount === 0n) {
      incoming.isMatched = true;
      this.orderIndex.delete(incoming.order.commitment);
    }

    return matches;
  }

  /**
   * Insert an order into the appropriate sorted book
   */
  private insertIntoBook(entry: OrderBookEntry): void {
    const pairId = entry.order.tokenPairId;

    if (entry.order.side === 0) {
      // Buy side: sort descending by price, then ascending by timestamp
      if (!this.buyOrders.has(pairId)) {
        this.buyOrders.set(pairId, []);
      }
      const book = this.buyOrders.get(pairId)!;
      const insertIdx = this.findInsertIndex(book, entry, "buy");
      book.splice(insertIdx, 0, entry);
    } else {
      // Sell side: sort ascending by price, then ascending by timestamp
      if (!this.sellOrders.has(pairId)) {
        this.sellOrders.set(pairId, []);
      }
      const book = this.sellOrders.get(pairId)!;
      const insertIdx = this.findInsertIndex(book, entry, "sell");
      book.splice(insertIdx, 0, entry);
    }
  }

  /**
   * Binary search for insert position in sorted book
   */
  private findInsertIndex(
    book: OrderBookEntry[],
    entry: OrderBookEntry,
    side: "buy" | "sell"
  ): number {
    let lo = 0;
    let hi = book.length;

    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      const cmp = this.compareOrders(entry, book[mid], side);

      if (cmp <= 0) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }

    return lo;
  }

  /**
   * Compare two orders for sorting
   * Buy side: higher price first, then earlier timestamp
   * Sell side: lower price first, then earlier timestamp
   */
  private compareOrders(
    a: OrderBookEntry,
    b: OrderBookEntry,
    side: "buy" | "sell"
  ): number {
    if (a.order.price !== b.order.price) {
      if (side === "buy") {
        // Descending by price for buys
        return a.order.price > b.order.price ? -1 : 1;
      } else {
        // Ascending by price for sells
        return a.order.price < b.order.price ? -1 : 1;
      }
    }
    // Same price: earlier timestamp first (ascending)
    return a.order.timestamp - b.order.timestamp;
  }
}
