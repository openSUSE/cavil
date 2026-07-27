<template>
  <div class="dropdown template-picker">
    <button
      class="template-picker-btn"
      type="button"
      id="template-picker-btn"
      data-bs-toggle="dropdown"
      aria-expanded="false"
      title="Insert a comment template"
    >
      <i class="fa-solid fa-file-lines" aria-hidden="true"></i>
      Templates
    </button>
    <ul class="dropdown-menu dropdown-menu-end template-picker-menu" aria-labelledby="template-picker-btn">
      <li v-for="template in templates" :key="template.id">
        <button class="dropdown-item template-picker-item" type="button" @click="$emit('select', template)">
          {{ template.name }}
        </button>
      </li>
      <template v-if="manageUrl !== null">
        <li><hr class="dropdown-divider" /></li>
        <li><a :href="manageUrl" class="dropdown-item template-picker-manage">Manage templates&hellip;</a></li>
      </template>
    </ul>
  </div>
</template>

<script>
export default {
  name: 'TemplatePicker',
  props: {
    // Only shown to reviewers who can curate, everyone else just picks
    manageUrl: {type: String, default: null},
    templates: {type: Array, required: true}
  },
  emits: ['select']
};
</script>

<style scoped>
.template-picker-btn {
  align-items: center;
  background: rgba(255, 255, 255, 0.92);
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 1px 2px rgba(31, 35, 40, 0.08);
  color: #1f2328;
  cursor: pointer;
  display: inline-flex;
  font-size: 13px;
  gap: 0.35rem;
  height: 28px;
  padding: 0 0.6rem;
  transition:
    background-color 0.15s,
    box-shadow 0.15s,
    color 0.15s;
}
.template-picker-btn:hover {
  background: #ffffff;
  box-shadow: 0 2px 4px rgba(31, 35, 40, 0.12);
  color: #0969da;
}
.template-picker-btn:focus {
  border-color: #0969da;
  box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.3);
  color: #0969da;
  outline: none;
}
.template-picker-menu {
  font-size: 14px;
  max-height: 20rem;
  overflow-y: auto;
}
.template-picker-manage {
  color: #57606a;
  font-size: 13px;
}
</style>
