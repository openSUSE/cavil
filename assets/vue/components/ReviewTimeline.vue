<template>
  <div class="review-timeline">
    <span v-for="(item, index) in items" :key="item.label" class="review-timeline-step">
      <span
        v-if="index > 0"
        :class="['review-timeline-connector', {'is-pending': item.pending}]"
        :style="item.width ? {flexBasis: item.width} : null"
      >
        <span v-if="item.gap" class="review-timeline-gap">{{ item.gap }}</span>
      </span>
      <span
        :class="[
          'review-timeline-point',
          {'is-pending': item.pending, 'is-first': index === 0, 'is-last': index === items.length - 1},
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
  const [unit, size] = UNITS.find(([, size]) => seconds >= size) ?? UNITS[3];
  const count = Math.max(1, Math.round(seconds / size));
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
      let firstPending = true;
      return this.steps.map(step => {
        const item = {...step};
        if (step.pending) {
          if (firstPending && previous !== null) {
            item.when = step.waiting ? `waiting ${duration(Date.now() / 1000 - previous)}` : 'in progress';
          }
          firstPending = false;
          return item;
        }
        if (step.epoch === null) return item;

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
        if (previous !== null) {
          const seconds = Math.max(0, step.epoch - previous);
          item.gap = duration(seconds);
          // Log scale, so weeks of waiting read longer than a minute of unpacking without crushing the rest
          item.width = `${(2.5 + 1.3 * Math.log10(1 + seconds)).toFixed(2)}rem`;
        }
        previous = step.epoch;
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
  flex-wrap: wrap;
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
.is-first .review-timeline-track::before {
  display: none;
}
.is-last .review-timeline-track::after {
  border-top-color: transparent;
}
.is-pending .review-timeline-track::before,
.is-trail-pending .review-timeline-track::after,
.review-timeline-connector.is-pending {
  border-top-style: dashed;
}
.review-timeline-dot {
  background: var(--cavil-fg-muted);
  border: 2px solid var(--cavil-fg-muted);
  border-radius: 50%;
  flex: none;
  height: 9px;
  width: 9px;
}
.is-pending .review-timeline-dot {
  background: var(--cavil-canvas);
  border-color: var(--cavil-border-strong);
}
.is-success .review-timeline-dot {
  background: var(--cavil-success);
  border-color: var(--cavil-success);
}
.is-danger .review-timeline-dot {
  background: var(--cavil-danger);
  border-color: var(--cavil-danger);
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
.review-timeline-when {
  color: var(--cavil-fg-disabled);
  font-size: 12px;
}
.review-timeline-connector {
  flex: none;
  flex-basis: 2.5rem;
  margin-top: 6px;
  position: relative;
}
.review-timeline-connector.is-pending {
  flex-basis: 1.5rem;
}
.review-timeline-gap {
  bottom: 3px;
  color: var(--cavil-fg-subtle);
  font-size: 11px;
  left: 50%;
  position: absolute;
  transform: translateX(-50%);
  white-space: nowrap;
}
</style>
