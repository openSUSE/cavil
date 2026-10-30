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
    hasCve() {
      return (this.tags ?? []).includes('CVE');
    }
  }
};
</script>
