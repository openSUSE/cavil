<template>
  <span v-if="hasCve" class="badge cavil-cve-badge" title="Fixes a security issue">CVE</span>
</template>

<script>
export default {
  name: 'CveBadge',
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
