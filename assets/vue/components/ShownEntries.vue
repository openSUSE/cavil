<template>
  <div>Showing {{ start }} to {{ end }} of {{ total }} entries</div>
</template>

<script>
export default {
  name: 'ShownEntries',
  props: {
    end: {type: Number, required: true},
    start: {type: Number, required: true},
    total: {type: Number, required: true}
  }
};
</script>
