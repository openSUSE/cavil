<template>
  <div v-if="priority >= 8" class="cavil-badge badge badge-danger">{{ priority }}</div>
  <div v-else-if="priority >= 5" class="cavil-badge badge badge-warning">{{ priority }}</div>
  <div v-else class="cavil-badge badge badge-success">{{ priority }}</div>
</template>

<script>
export default {
  name: 'PriorityBadge',
  props: {
    priority: {type: Number, required: true}
  }
};
</script>

<style>
.cavil-badge {
  padding: 0.75em;
  padding-left: 1.5em;
  padding-right: 1.5em;
}
</style>
