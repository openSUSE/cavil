<template>
  <button
    v-if="hasCve"
    type="button"
    class="badge cavil-cve-badge"
    title="Filter to security fixes"
    @click="$emit('filter', 'tag=CVE')"
  >
    CVE
  </button>
</template>

<script>
export default {
  name: 'CveBadge',
  emits: ['filter'],
  props: {
    tags: {
      type: Array,
      default: () => []
    }
  },
  computed: {
    // Matches the single "CVE" marker as well as any legacy per-id "CVE-..." tags.
    hasCve() {
      return (this.tags ?? []).some(tag => /^CVE(-|$)/i.test(tag));
    }
  }
};
</script>
