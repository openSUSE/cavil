<template>
  <div class="tag-input">
    <div class="report-note-tag-editor" :data-note-tag-editor="dataKey">
      <span
        v-for="(t, i) in modelValue"
        :key="t"
        class="report-note-tag report-note-tag-removable"
        :data-note-tag-chip="t"
      >
        {{ t }}
        <button
          type="button"
          class="report-note-tag-remove"
          :data-note-tag-remove="t"
          :aria-label="`Remove tag ${t}`"
          @click="removeTag(i)"
        >
          ×
        </button>
      </span>
      <input
        ref="input"
        v-model="draft"
        type="text"
        class="report-note-tag-input"
        :class="{'report-note-tag-input-error': error}"
        :placeholder="placeholder"
        autocomplete="off"
        data-note-tag-input
        @input="onInput"
        @focus="open = true"
        @keydown="onKeydown"
        @blur="onBlur"
      />
    </div>
    <ul v-if="showPopover" class="tag-input-suggestions" data-tag-suggestions>
      <li
        v-for="(s, i) in filteredSuggestions"
        :key="s.tag"
        :class="['tag-input-suggestion', {'is-active': i === highlight}]"
        :data-tag-suggestion="s.tag"
        @mousedown.prevent="selectSuggestion(s)"
        @mousemove="highlight = i"
      >
        <span class="tag-input-suggestion-name">{{ s.tag }}</span>
        <span class="tag-input-suggestion-count">{{ s.count }}</span>
      </li>
    </ul>
  </div>
</template>

<script>
export default {
  name: 'TagInput',
  props: {
    modelValue: {type: Array, default: () => []},
    suggestions: {type: Array, default: () => []},
    placeholder: {type: String, default: 'Add a tag…'},
    allowNew: {type: Boolean, default: true},
    maxTags: {type: Number, default: 16},
    maxLength: {type: Number, default: 32},
    dataKey: {type: String, default: ''}
  },
  emits: ['update:modelValue'],
  data() {
    return {
      draft: '',
      error: false,
      open: false,
      highlight: -1
    };
  },
  computed: {
    filteredSuggestions() {
      const query = this.draft.trim().toLowerCase();
      let list = this.suggestions.filter(s => !this.modelValue.includes(s.tag));
      if (query) list = list.filter(s => s.tag.toLowerCase().includes(query));
      return list.slice(0, 8);
    },
    showPopover() {
      return this.open && this.filteredSuggestions.length > 0;
    }
  },
  methods: {
    onInput() {
      this.open = true;
      this.highlight = -1;
    },
    onKeydown(event) {
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        this.open = true;
        this.highlight = Math.min(this.highlight + 1, this.filteredSuggestions.length - 1);
      } else if (event.key === 'ArrowUp') {
        event.preventDefault();
        this.highlight = Math.max(this.highlight - 1, -1);
      } else if (event.key === 'Enter' || event.key === ',') {
        event.preventDefault();
        if (this.open && this.highlight >= 0 && this.filteredSuggestions[this.highlight]) {
          this.selectSuggestion(this.filteredSuggestions[this.highlight]);
        } else {
          this.commitDraft();
        }
      } else if (event.key === 'Escape') {
        this.open = false;
        this.highlight = -1;
      } else if (event.key === 'Backspace' && !this.draft && this.modelValue.length) {
        event.preventDefault();
        this.removeTag(this.modelValue.length - 1);
      }
    },
    onBlur() {
      // Defer so a suggestion mousedown (which keeps focus via .prevent) and any
      // pending click resolve before we tear the popover down.
      this.commitDraft();
      this.open = false;
      this.highlight = -1;
    },
    selectSuggestion(s) {
      this.addTag(s.tag);
      this.draft = '';
      this.highlight = -1;
      // Keep the input focused so the reviewer can add several tags in a row.
      this.$refs.input?.focus();
    },
    // Flush a typed-but-uncommitted draft. Exposed so a parent form can call it
    // before submitting (mirrors the old commitTag()-on-submit behavior). New
    // free-text tags are only accepted when allowNew is set.
    commitDraft() {
      const value = this.draft.trim();
      this.draft = '';
      if (!value || !this.allowNew) return;
      this.addTag(value);
    },
    addTag(value) {
      // Mirrors server-side caps in Cavil::Util::validate_tags so the UI fails
      // loudly here instead of silently dropping at the API.
      if (value.length > this.maxLength || this.modelValue.length >= this.maxTags) {
        this.error = true;
        setTimeout(() => (this.error = false), 600);
        return;
      }
      if (this.modelValue.includes(value)) return;
      this.$emit('update:modelValue', [...this.modelValue, value]);
    },
    removeTag(index) {
      const next = this.modelValue.slice();
      next.splice(index, 1);
      this.$emit('update:modelValue', next);
    }
  }
};
</script>

<style>
/* Chip editor styling lives here so TagInput is the single source of truth for
   the tag widget; ReportNotes imports this component, so its read-only display
   pills (.report-note-tag) pick up these rules too. */
.tag-input {
  position: relative;
}
.report-note-tag {
  background: #eaeef2;
  border: 1px solid rgba(110, 119, 129, 0.25);
  border-radius: 2em;
  color: #57606a;
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.01em;
  line-height: 18px;
  padding: 0 8px;
  white-space: nowrap;
}
.report-note-tag-editor {
  align-items: center;
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-bottom: 8px;
  padding: 6px 8px;
}
.report-note-tag-editor:focus-within {
  border-color: #0969da;
  box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.15);
}
.report-note-tag.report-note-tag-removable {
  align-items: center;
  display: inline-flex;
  gap: 4px;
  padding-right: 4px;
}
.report-note-tag-remove {
  background: transparent;
  border: 0;
  border-radius: 50%;
  color: #57606a;
  cursor: pointer;
  font-size: 14px;
  line-height: 1;
  padding: 0 4px;
}
.report-note-tag-remove:hover {
  background: rgba(208, 215, 222, 0.5);
  color: #1f2328;
}
.report-note-tag-input {
  background: transparent;
  border: 0;
  color: #1f2328;
  flex: 1 1 120px;
  font-size: 13px;
  min-width: 80px;
  outline: none;
  padding: 2px 4px;
}
.report-note-tag-input::placeholder {
  color: #8c959f;
}
.report-note-tag-input-error {
  animation: report-note-tag-shake 0.3s ease-in-out;
}
@keyframes report-note-tag-shake {
  0%,
  100% {
    background: transparent;
  }
  50% {
    background: #ffebe9;
  }
}
.tag-input-suggestions {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(140, 149, 159, 0.2);
  left: 0;
  list-style: none;
  margin: -4px 0 0;
  max-height: 240px;
  overflow-y: auto;
  padding: 4px;
  position: absolute;
  right: 0;
  top: 100%;
  z-index: 20;
}
.tag-input-suggestion {
  align-items: center;
  border-radius: 4px;
  color: #1f2328;
  cursor: pointer;
  display: flex;
  font-size: 13px;
  gap: 8px;
  justify-content: space-between;
  padding: 5px 8px;
}
.tag-input-suggestion.is-active {
  background: #ddf4ff;
}
.tag-input-suggestion-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.tag-input-suggestion-count {
  color: #8c959f;
  font-size: 11px;
  font-variant-numeric: tabular-nums;
}
</style>
