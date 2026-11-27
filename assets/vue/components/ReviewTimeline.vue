<template>
  <div class="review-timeline">
    <span v-for="(item, index) in items" :key="item.label" class="review-timeline-step">
      <span
        v-if="index > 0"
        :class="['review-timeline-connector', {'is-pending': item.pending, 'has-gap': item.gap}]"
        :style="item.weight ? {flexGrow: item.weight} : null"
      >
        <span v-if="item.gap" class="review-timeline-gap">{{ item.gap }}</span>
      </span>
      <span
        :class="[
          'review-timeline-point',
          {'is-pending': item.pending, 'is-first': index === 0, 'is-last': index === items.length - 1},
          {'is-current': item.current},
          {'is-trail-pending': items[index + 1]?.pending},
          item.tone ? `is-${item.tone}` : null
        ]"
        :title="item.title"
      >
        <span class="review-timeline-track"><span class="review-timeline-dot"></span></span>
        <span class="review-timeline-label">{{ item.label }}</span>
        <span v-if="item.when" class="review-timeline-when">{{ item.when }}</span>
      </span>
    </span>
  </div>
</template>

<script>
import moment from 'moment';

const UNITS = [
  ['day', 86400],
  ['hour', 3600],
  ['min', 60],
  ['sec', 1]
];

function duration(seconds) {
  let index = UNITS.findIndex(([, size]) => seconds >= size);
  if (index === -1) index = UNITS.length - 1;
  let count = Math.max(1, Math.round(seconds / UNITS[index][1]));
  // Rounding up can reach the next unit, 23.6 hours is "1 day" and not "24 hours"
  if (index > 0 && count * UNITS[index][1] >= UNITS[index - 1][1]) [index, count] = [index - 1, 1];
  const [unit, size] = UNITS[index];
  return `${count} ${unit}${count > 1 && size >= 3600 ? 's' : ''}`;
}

export default {
  name: 'ReviewTimeline',
  props: {
    // [{label, epoch, pending, tone}], done steps in time order followed by the pending ones
    steps: {type: Array, required: true}
  },
  computed: {
    items() {
      let previous = null;
      let adjacent = false;
      let firstPending = true;
      return this.steps.map(step => {
        const item = {...step};
        if (step.pending) {
          if (firstPending) {
            item.current = true;
            if (previous !== null) {
              item.when = step.waiting ? `waiting ${duration(Date.now() / 1000 - previous)}` : 'in progress';
            }
          }
          firstPending = false;
          return item;
        }
        if (step.epoch === null) {
          adjacent = false;
          return item;
        }

        const time = moment(step.epoch * 1000);
        item.when = time.calendar({
          sameDay: 'HH:mm',
          lastDay: '[yesterday]',
          lastWeek: 'ddd',
          sameElse(now) {
            return this.year() === now.year() ? 'MMM D' : 'MMM D, YYYY';
          }
        });
        item.title = time.format('YYYY-MM-DD HH:mm');
        // A duration only between two neighbouring times, across an untimed step it would read as that step's
        if (adjacent) {
          const seconds = Math.max(0, step.epoch - previous);
          item.gap = duration(seconds);
          // Log scale, so weeks of waiting read longer than a minute of unpacking without crushing the rest
          item.weight = (2.5 + 1.3 * Math.log10(1 + seconds)).toFixed(2);
        }
        previous = step.epoch;
        adjacent = true;
        return item;
      });
    }
  }
};
</script>

<style scoped>
.review-timeline {
  align-items: flex-start;
  display: flex;
  padding-top: 0.15rem;
}
.review-timeline-step {
  display: contents;
}
.review-timeline-point {
  align-items: center;
  display: flex;
  flex-direction: column;
  line-height: 1.35;
  white-space: nowrap;
}
.review-timeline-track {
  align-items: center;
  align-self: stretch;
  display: flex;
  height: 13px;
}
.review-timeline-track::before,
.review-timeline-track::after,
.review-timeline-connector {
  border-top: 1px solid var(--cavil-border);
}
.review-timeline-track::before,
.review-timeline-track::after {
  content: '';
  flex: 1;
  min-width: 0.5rem;
}
.review-timeline-point.is-first {
  align-items: flex-start;
}
.review-timeline-point.is-last {
  align-items: flex-end;
}
.is-first .review-timeline-track::before,
.is-last .review-timeline-track::after {
  display: none;
}
.is-pending .review-timeline-track::before,
.is-trail-pending .review-timeline-track::after,
.review-timeline-connector.is-pending {
  border-top-style: dashed;
}
/* Done steps are rings filled at the centre, pending ones hollow */
.review-timeline-dot {
  --dot: var(--cavil-fg-muted);
  background: var(--dot);
  border: 2px solid var(--dot);
  border-radius: 50%;
  box-shadow: inset 0 0 0 2px var(--cavil-canvas);
  flex: none;
  height: 13px;
  width: 13px;
}
.is-pending .review-timeline-dot {
  --dot: var(--cavil-border-strong);
  background: var(--cavil-canvas);
}
.is-current .review-timeline-dot {
  --dot: var(--cavil-accent);
  box-shadow: 0 0 0 3px rgba(var(--cavil-accent-rgb), 0.18);
}
.is-success .review-timeline-dot {
  --dot: var(--cavil-success);
}
.is-danger .review-timeline-dot {
  --dot: var(--cavil-danger);
}
.review-timeline-label {
  color: var(--cavil-fg-muted);
  font-size: 12px;
  font-weight: 500;
  margin-top: 0.2rem;
}
.is-pending .review-timeline-label {
  color: var(--cavil-fg-disabled);
  font-weight: 400;
}
.is-current .review-timeline-label {
  color: var(--cavil-fg);
  font-weight: 600;
}
.review-timeline-when {
  color: var(--cavil-fg-disabled);
  font-size: 12px;
}
/* Spans the full width: connectors grow by their weight and never wrap, shrinking down to what their gap label needs */
.review-timeline-connector {
  flex: 2.5 1 0;
  margin-top: 6px;
  min-width: 1.5rem;
  position: relative;
}
.review-timeline-connector.has-gap {
  min-width: 4rem;
}
.review-timeline-gap {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 2em;
  color: var(--cavil-fg-muted);
  font-size: 11px;
  left: 50%;
  line-height: 1;
  padding: 0.15rem 0.45rem;
  position: absolute;
  top: 0;
  transform: translate(-50%, -50%);
  white-space: nowrap;
}
</style>
