<template>
  <div class="cavil-settings">
    <div class="cavil-settings-layout">
      <nav class="cavil-settings-nav" aria-label="Settings sections">
        <div v-for="group in groups" :key="group.name" class="cavil-settings-nav-group">
          <div class="cavil-settings-nav-heading">{{ group.name }}</div>
          <a
            v-for="item in group.sections"
            :key="item.id"
            :href="`/settings/${item.id}`"
            :class="['cavil-settings-nav-item', {active: item.id === section}]"
            :aria-current="item.id === section ? 'page' : null"
          >
            <i :class="item.icon" aria-hidden="true"></i>
            {{ item.label }}
          </a>
        </div>
      </nav>
      <div class="cavil-settings-main">
        <SettingsApiKeys v-if="section === 'api-keys'" />
        <SettingsAutoAccept v-else-if="section === 'auto-accept'" />
        <SettingsExcludedFiles v-else-if="section === 'excluded-files'" />
        <SettingsCommentTemplates v-else-if="section === 'comment-templates'" />
        <SettingsBotTokens v-else-if="section === 'bot-tokens'" />
        <SettingsSbom v-else-if="section === 'sbom'" />
      </div>
    </div>
  </div>
</template>

<script>
import SettingsApiKeys from './components/SettingsApiKeys.vue';
import SettingsAutoAccept from './components/SettingsAutoAccept.vue';
import SettingsBotTokens from './components/SettingsBotTokens.vue';
import SettingsCommentTemplates from './components/SettingsCommentTemplates.vue';
import SettingsExcludedFiles from './components/SettingsExcludedFiles.vue';
import SettingsSbom from './components/SettingsSbom.vue';

const SECTIONS = [
  {id: 'api-keys', label: 'API keys', icon: 'fa-solid fa-key', group: 'Personal'},
  {id: 'auto-accept', label: 'Automatic acceptance', icon: 'fa-solid fa-circle-check', group: 'Reviews', cap: 'infra'},
  {
    id: 'excluded-files',
    label: 'Excluded files',
    icon: 'fa-solid fa-file-circle-xmark',
    group: 'Reviews',
    cap: 'infra'
  },
  {
    id: 'comment-templates',
    label: 'Comment templates',
    icon: 'fa-solid fa-comment-dots',
    group: 'Reviews',
    cap: 'curate'
  },
  {id: 'bot-tokens', label: 'Bot tokens', icon: 'fa-solid fa-robot', group: 'Integrations', cap: 'infra'},
  {id: 'sbom', label: 'SBOM', icon: 'fa-solid fa-file-shield', group: 'Integrations', cap: 'infra'}
];

export default {
  name: 'SettingsPage',
  components: {
    SettingsApiKeys,
    SettingsAutoAccept,
    SettingsBotTokens,
    SettingsCommentTemplates,
    SettingsExcludedFiles,
    SettingsSbom
  },
  props: {
    canCurate: {type: Boolean, default: false},
    canInfra: {type: Boolean, default: false},
    section: {type: String, required: true}
  },
  computed: {
    groups() {
      const allowed = {infra: this.canInfra, curate: this.canCurate};
      const groups = [];
      for (const item of SECTIONS.filter(item => !item.cap || allowed[item.cap])) {
        if (groups.at(-1)?.name !== item.group) groups.push({name: item.group, sections: []});
        groups.at(-1).sections.push(item);
      }
      return groups;
    }
  }
};
</script>
