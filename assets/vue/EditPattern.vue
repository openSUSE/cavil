<template>
  <div class="edit-pattern">
    <PatternEditor :pattern="currentPattern" />
  </div>
</template>

<script>
import PatternEditor from './components/PatternEditor.vue';

export default {
  name: 'EditPattern',
  components: {PatternEditor}
};
</script>
