<template>
  <div class="cavil-settings">
    <div class="cavil-settings-layout">
      <nav class="cavil-settings-nav" aria-label="Settings sections">
        <a
          v-for="item in sections"
          :key="item.id"
          :href="`/settings/${item.id}`"
          :class="['cavil-settings-nav-item', {active: item.id === section}]"
          :aria-current="item.id === section ? 'page' : null"
        >
          <i :class="item.icon" aria-hidden="true"></i>
          {{ item.label }}
        </a>
      </nav>
      <div class="cavil-settings-main">
        <SettingsAutoAccept v-if="section === 'auto-accept'" />
        <SettingsExcludedFiles v-else-if="section === 'excluded-files'" />
        <SettingsCommentTemplates v-else-if="section === 'comment-templates'" />
      </div>
    </div>
  </div>
</template>

<script>
import SettingsAutoAccept from './components/SettingsAutoAccept.vue';
import SettingsCommentTemplates from './components/SettingsCommentTemplates.vue';
import SettingsExcludedFiles from './components/SettingsExcludedFiles.vue';

export default {
  name: 'SettingsPage',
  components: {SettingsAutoAccept, SettingsCommentTemplates, SettingsExcludedFiles},
  props: {
    canInfra: {type: Boolean, default: false},
    section: {type: String, required: true}
  },
  computed: {
    sections() {
      return [
        {id: 'auto-accept', label: 'Automatic acceptance', icon: 'fa-solid fa-circle-check', infra: true},
        {id: 'excluded-files', label: 'Excluded files', icon: 'fa-solid fa-file-circle-xmark', infra: true},
        {id: 'comment-templates', label: 'Comment templates', icon: 'fa-solid fa-comment-dots'}
      ].filter(section => this.canInfra || !section.infra);
    }
  }
};
</script>
