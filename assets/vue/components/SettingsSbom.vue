<template>
  <section>
    <div class="cavil-settings-header">
      <h3>SBOM</h3>
      <p>
        The organisation the SPDX SBOMs name as their creator. BSI TR-03183-2 asks for an email address, or a web
        address when there is none. An empty field uses the value shown in it.
      </p>
      <p>Changes apply to SBOMs generated from now on, existing ones follow with the next reindex of their package.</p>
    </div>

    <LegalLoading v-if="form === null" message="Loading settings..." size="small" />
    <form v-else @submit.prevent="save()">
      <div v-for="field in fields" :key="field.name" class="cavil-settings-rule">
        <label :for="field.id" class="cavil-settings-label">{{ field.label }}</label>
        <SettingsDefaultLabel :name="field.name" :custom="custom" @reset="reset" />
        <p class="cavil-settings-help">{{ field.help }}</p>
        <div class="cavil-settings-nested">
          <input
            :id="field.id"
            v-model="form[field.name]"
            :type="field.type"
            class="form-control cavil-settings-text"
            :placeholder="response.fallbacks?.[field.fallback] ?? ''"
          />
          <div v-if="errors[field.name]" class="cavil-settings-error">{{ errors[field.name] }}</div>
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
import ToastNotifier from './ToastNotifier.vue';
import SettingsForm from '../mixins/settingsForm.js';

export default {
  name: 'SettingsSbom',
  components: {LegalLoading, SettingsDefaultLabel, SettingsLastChange, ToastNotifier},
  mixins: [SettingsForm],
  data() {
    return {
      settingsUrl: '/settings/sbom.json',
      fields: [
        {
          name: 'sbom_creator_name',
          id: 'sbom-creator-name',
          label: 'Organisation',
          help: 'The name of the organisation that runs this Cavil instance.',
          type: 'text',
          fallback: 'name'
        },
        {
          name: 'sbom_creator_email',
          id: 'sbom-creator-email',
          label: 'Email address',
          help: 'Where questions about an SBOM can be sent.',
          type: 'email',
          fallback: 'email'
        },
        {
          name: 'sbom_creator_url',
          id: 'sbom-creator-url',
          label: 'Web address',
          help: 'Only used when there is no email address.',
          type: 'url',
          fallback: 'url'
        }
      ]
    };
  }
};
</script>
