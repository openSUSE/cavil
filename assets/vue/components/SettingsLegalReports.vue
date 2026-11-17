<template>
  <section>
    <div class="cavil-settings-header">
      <h3>Legal reports</h3>
      <p>Decide how Cavil classifies the files in a legal report.</p>
      <p>Reports of the packages you add or remove are rebuilt when you save.</p>
    </div>

    <LegalLoading v-if="form === null" message="Loading settings..." size="small" />
    <form v-else @submit.prevent="save()">
      <div class="cavil-settings-rule">
        <label for="build-tool-packages" class="cavil-settings-label">Packages that ship their build files</label>
        <SettingsDefaultLabel :name="'build_tool_packages'" :custom="custom" @reset="reset" />
        <p class="cavil-settings-help">
          Build files such as configure scripts, m4 macros and Makefile templates normally never end up in a binary
          package, so a license found only in them reads "only in build files" and its incompatibilities rank lower.
          Build tools are the exception, their build files are what they ship. Each name covers its package family,
          other versions of the same software included. Press Enter after each name.
        </p>
        <div class="cavil-settings-nested" id="build-tool-packages">
          <TagInput
            v-model="form.build_tool_packages"
            :max-length="255"
            :max-tags="1000"
            placeholder="Add a package name"
            data-key="build-tool-packages"
          />
          <div v-if="errors.build_tool_packages" class="cavil-settings-error">{{ errors.build_tool_packages }}</div>
        </div>
      </div>

      <div class="cavil-settings-footer">
        <button type="submit" class="btn btn-success" id="settings-save" :disabled="!dirty || saving">
          Save changes
        </button>
        <SettingsLastChange :change="lastChange" empty="Using default values" />
      </div>
    </form>
    <ToastNotifier ref="toaster" />
  </section>
</template>

<script>
import LegalLoading from './LegalLoading.vue';
import SettingsDefaultLabel from './SettingsDefaultLabel.vue';
import SettingsLastChange from './SettingsLastChange.vue';
import TagInput from './TagInput.vue';
import ToastNotifier from './ToastNotifier.vue';
import SettingsForm from '../mixins/settingsForm.js';

export default {
  name: 'SettingsLegalReports',
  components: {LegalLoading, SettingsDefaultLabel, SettingsLastChange, TagInput, ToastNotifier},
  mixins: [SettingsForm],
  data() {
    return {settingsUrl: '/settings/legal-reports.json'};
  }
};
</script>
