<template>
  <div class="pattern-editor" :class="{'pattern-editor-inline': inline}">
    <div v-if="error" class="alert alert-danger" role="alert">{{ error }}</div>

    <div v-if="!isNew && showMatchCount" class="row">
      <div class="col mb-3 edit-pattern-match-count">
        <span v-if="matchCount === null && matchCountError === null">
          <i class="fa-solid fa-rotate fa-spin"></i> Loading match count
        </span>
        <span v-else-if="matchCountError !== null" class="text-danger">{{ matchCountError }}</span>
        <span v-else-if="matchCount.matches === 0">This pattern has no matches.</span>
        <span v-else>
          This pattern has <b>{{ matchCount.matches }}</b> {{ matchCount.matches === 1 ? 'match' : 'matches' }} in
          <b>{{ matchCount.packages }}</b>
          <a :href="`/search?pattern=${pattern.id}`">{{ matchCount.packages === 1 ? 'package' : 'packages' }}</a
          >.
        </span>
      </div>
    </div>

    <div class="pattern-editor-tabs" role="tablist">
      <button
        type="button"
        class="pattern-editor-tab"
        :class="{active: activeTab === 'edit'}"
        role="tab"
        :aria-selected="activeTab === 'edit'"
        data-tab="edit"
        @click="setActiveTab('edit')"
      >
        <i class="fa-solid fa-pen-to-square"></i> Edit
      </button>
      <button
        type="button"
        class="pattern-editor-tab"
        :class="{active: activeTab === 'closest'}"
        role="tab"
        :aria-selected="activeTab === 'closest'"
        data-tab="closest"
        :disabled="closest === null"
        @click="setActiveTab('closest')"
      >
        <i class="fa-solid fa-magnifying-glass"></i>
        Closest match
        <span v-if="closest !== null" class="pattern-editor-tab-badge">{{ closest.similarity }}%</span>
      </button>
    </div>

    <div class="pattern-editor-tab-content">
      <div
        class="pattern-editor-tab-pane"
        :class="{'is-active': activeTab === 'edit'}"
        :aria-hidden="activeTab !== 'edit'"
      >
        <div class="row">
          <form :action="formAction" method="POST" @submit="onSubmit">
            <div class="col mb-3">
              <label class="form-label" for="license">License</label>
              <input v-model="form.license" type="text" name="license" id="license" class="form-control" />
            </div>
            <div v-if="!isNew && showSpdx" class="col mb-3">
              <label class="form-label" for="spdx">SPDX</label>
              <input :value="pattern.spdx" type="text" id="spdx" class="form-control" disabled />
            </div>
            <div class="col mb-3">
              <label class="form-label" for="pattern-text">Pattern</label>
              <PatternCodeMirror v-model="form.pattern" />
              <textarea name="pattern" :value="form.pattern" class="edit-pattern-hidden"></textarea>
            </div>

            <div class="col mb-3">
              <div class="row">
                <div class="col-lg-2 mb-3">
                  <div class="form-floating">
                    <select v-model="form.risk" name="risk" id="risk" class="form-control">
                      <option v-for="r in 10" :key="r - 1" :value="String(r - 1)">{{ r - 1 }}</option>
                    </select>
                    <label for="risk" class="form-label">Risk</label>
                  </div>
                </div>
                <div class="col-lg-2">
                  <div class="form-check">
                    <input
                      v-model="form.patent"
                      type="checkbox"
                      class="form-check-input"
                      id="patent"
                      name="patent"
                      value="1"
                    />
                    <label class="form-check-label" for="patent">Patent</label>
                  </div>
                  <div class="form-check">
                    <input
                      v-model="form.trademark"
                      type="checkbox"
                      class="form-check-input"
                      id="trademark"
                      name="trademark"
                      value="1"
                    />
                    <label class="form-check-label" for="trademark">Trademark</label>
                  </div>
                </div>
                <div class="col-lg-2">
                  <div class="form-check">
                    <input
                      v-model="form.export_restricted"
                      type="checkbox"
                      class="form-check-input"
                      id="export_restricted"
                      name="export_restricted"
                      value="1"
                    />
                    <label class="form-check-label" for="export_restricted">Export Restricted</label>
                  </div>
                </div>
              </div>
            </div>

            <div class="col mb-3">
              <label class="form-label" for="packname">Package</label>
              <input v-model="form.packname" type="text" name="packname" id="packname" class="form-control" />
              <div id="packageHelp" class="form-text">Leave this field empty to apply pattern to all packages</div>
            </div>

            <div class="col mb-4 pattern-editor-actions">
              <button type="submit" class="btn btn-primary" :disabled="saving">
                <i v-if="saving" class="fa-solid fa-rotate fa-spin"></i>
                {{ isNew ? 'Create' : inline ? 'Save changes' : 'Update' }}
              </button>
              <button v-if="inline" type="button" class="btn btn-secondary" :disabled="saving" @click="$emit('cancel')">
                Cancel
              </button>
              <button
                v-if="!isNew"
                type="button"
                class="del-pattern btn btn-danger btn-sm"
                :disabled="saving"
                @click="onDelete"
              >
                Delete
              </button>
            </div>
          </form>
        </div>
      </div>
      <div
        class="pattern-editor-tab-pane"
        :class="{'is-active': activeTab === 'closest'}"
        :aria-hidden="activeTab !== 'closest'"
      >
        <ClosestPattern :pattern="form.pattern" :exclude-id="pattern.id ?? null" @loaded="onClosestLoaded" />
      </div>
    </div>
  </div>
</template>

<script>
import ClosestPattern from './ClosestPattern.vue';
import PatternCodeMirror from './PatternCodeMirror.vue';
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'PatternEditor',
  components: {ClosestPattern, PatternCodeMirror},
  props: {
    pattern: {type: Object, required: true},
    inline: {type: Boolean, default: false},
    showMatchCount: {type: Boolean, default: true},
    showSpdx: {type: Boolean, default: true}
  },
  emits: ['saved', 'deleted', 'cancel'],
  data() {
    return {
      form: this.formFromPattern(this.pattern),
      activeTab: 'edit',
      closest: null,
      matchCount: null,
      matchCountError: null,
      saving: false,
      error: null,
      ua: new UserAgent({baseURL: window.location.href})
    };
  },
  computed: {
    isNew() {
      return this.pattern.id == null;
    },
    formAction() {
      return this.isNew ? '/licenses/create_pattern' : `/licenses/update_pattern/${this.pattern.id}`;
    }
  },
  mounted() {
    if (!this.isNew && this.showMatchCount) this.loadMatchCount();
  },
  methods: {
    formFromPattern(pattern) {
      return {
        license: pattern.license ?? '',
        pattern: pattern.pattern ?? '',
        risk: String(pattern.risk ?? 0),
        patent: !!pattern.patent,
        trademark: !!pattern.trademark,
        export_restricted: !!pattern.export_restricted,
        packname: pattern.packname ?? ''
      };
    },
    formPayload() {
      const form = {
        license: this.form.license,
        pattern: this.form.pattern,
        risk: this.form.risk,
        packname: this.form.packname
      };
      if (this.form.patent) form.patent = '1';
      if (this.form.trademark) form.trademark = '1';
      if (this.form.export_restricted) form.export_restricted = '1';
      return form;
    },
    async loadMatchCount() {
      try {
        const res = await this.ua.get(`/licenses/pattern/${this.pattern.id}/match_count.json`);
        if (!res.isSuccess) throw new Error(`HTTP ${res.statusCode}`);
        this.matchCount = await res.json();
      } catch (_error) {
        this.matchCountError = 'Could not load match count.';
      }
    },
    onClosestLoaded(closest) {
      this.closest = closest;
      if (closest === null && this.activeTab === 'closest') this.activeTab = 'edit';
    },
    setActiveTab(tab) {
      if (tab === 'closest' && this.closest === null) return;
      this.activeTab = tab;
    },
    async onSubmit(event) {
      if (!this.inline) return;
      event.preventDefault();
      if (this.isNew) return;
      this.error = null;
      this.saving = true;
      try {
        const res = await this.ua.post(`/licenses/pattern/${this.pattern.id}.json`, {form: this.formPayload()});
        if (!res.isSuccess) {
          const data = await res.json().catch(() => ({}));
          throw new Error(data.error || `Pattern update failed with HTTP ${res.statusCode}`);
        }
        this.$emit('saved');
      } catch (error) {
        this.error = error.message;
      } finally {
        this.saving = false;
      }
    },
    async onDelete() {
      if (!window.confirm('Sure to delete pattern?')) return;
      this.error = null;
      this.saving = true;
      try {
        const res = await this.ua.delete(`/licenses/remove_pattern/${this.pattern.id}`);
        if (!res.isSuccess) throw new Error('Failed to delete pattern.');
        if (this.inline) this.$emit('deleted');
        else window.location = '/licenses';
      } catch (error) {
        this.error = error.message;
      } finally {
        this.saving = false;
      }
    }
  },
  watch: {
    pattern(pattern) {
      this.form = this.formFromPattern(pattern);
      this.activeTab = 'edit';
      this.closest = null;
      this.matchCount = null;
      this.matchCountError = null;
      if (!this.isNew && this.showMatchCount) this.loadMatchCount();
    }
  }
};
</script>

<style scoped>
.edit-pattern-match-count {
  min-height: 1.5rem;
}
.edit-pattern-hidden {
  display: none;
}
.pattern-editor-tabs {
  border-bottom: 1px solid #d0d7de;
  display: flex;
  gap: 4px;
  margin-bottom: 16px;
}
.pattern-editor-tab {
  align-items: center;
  background: transparent;
  border: 1px solid transparent;
  border-bottom: 0;
  border-radius: 6px 6px 0 0;
  color: #57606a;
  cursor: pointer;
  display: inline-flex;
  font-size: 13px;
  font-weight: 500;
  gap: 6px;
  line-height: 1;
  margin-bottom: -1px;
  padding: 8px 14px;
  transition:
    background-color 0.15s,
    color 0.15s;
}
.pattern-editor-tab:hover:not(:disabled):not(.active) {
  background: #f3f5f7;
  color: #1f2328;
}
.pattern-editor-tab.active {
  background: #ffffff;
  border-color: #d0d7de;
  color: #1f2328;
  font-weight: 600;
}
.pattern-editor-tab:disabled {
  color: #8c959f;
  cursor: not-allowed;
}
.pattern-editor-tab-badge {
  background: #ddf4ff;
  border-radius: 10px;
  color: #0969da;
  font-size: 11px;
  font-weight: 600;
  margin-left: 2px;
  padding: 1px 7px;
}
.pattern-editor-tab:disabled .pattern-editor-tab-badge {
  background: #eaeef2;
  color: #8c959f;
}
.pattern-editor-tab-pane {
  display: none;
}
.pattern-editor-tab-pane.is-active {
  display: block;
}
.pattern-editor-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.del-pattern {
  margin-left: 0.25rem;
}
.pattern-editor-inline {
  background: #ffffff;
}
</style>
