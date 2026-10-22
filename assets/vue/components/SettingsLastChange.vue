<template>
  <p class="cavil-settings-last-change">
    <template v-if="change">Last changed by {{ change.login ?? 'Cavil' }} {{ when }}</template>
    <template v-else>{{ empty }}</template>
    - <a href="/audit?category=settings">History</a>
  </p>
</template>

<script>
import moment from 'moment';

export default {
  name: 'SettingsLastChange',
  props: {
    change: {type: Object, default: null},
    empty: {type: String, required: true}
  },
  computed: {
    when() {
      return moment(this.change.created_epoch * 1000).fromNow();
    }
  }
};
</script>
