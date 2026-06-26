<template>
  <div class="cavil-list-page mt-3">
    <header v-if="pageTitle" class="cavil-list-page-heading">
      <h2>{{ pageTitle }}</h2>
    </header>

    <section class="cavil-list-toolbar" :aria-label="filterAriaLabel">
      <form id="cavil-pkg-filter" class="cavil-list-filter" @submit.prevent="$emit('filter-submit')">
        <label :for="filterInputId">{{ filterLabel }}</label>
        <div class="cavil-list-filter-box">
          <i class="fa-solid fa-magnifying-glass" aria-hidden="true"></i>
          <input
            :id="filterInputId"
            :value="filter"
            type="search"
            class="form-control"
            :placeholder="filterPlaceholder"
            @input="$emit('update:filter', $event.target.value)"
          />
        </div>
      </form>
    </section>

    <section class="cavil-list-panel" aria-live="polite">
      <div class="cavil-list-header">
        <div class="cavil-list-title">
          <i :class="countIcon" aria-hidden="true"></i>
          <strong>{{ total.toLocaleString() }}</strong>
          <span>{{ total === 1 ? singular : plural }}</span>
        </div>
        <div class="cavil-list-actions">
          <div class="cavil-list-controls">
            <slot name="controls"></slot>
          </div>
          <div class="cavil-list-per-page">
            <slot name="per-page"></slot>
          </div>
        </div>
      </div>
      <div class="cavil-list-table-wrap">
        <slot></slot>
      </div>
    </section>

    <footer class="cavil-list-footer">
      <div id="cavil-pagination">
        <PaginationLinks
          :end="end"
          :start="start"
          :total="total"
          :current-page="currentPage"
          :total-pages="totalPages"
          @goto-page="$emit('goto-page', $event)"
        />
      </div>
    </footer>
  </div>
</template>

<script>
import PaginationLinks from './PaginationLinks.vue';

export default {
  name: 'CavilListLayout',
  components: {PaginationLinks},
  props: {
    currentPage: {type: Number, required: true},
    end: {type: Number, required: true},
    filter: {type: String, default: ''},
    filterAriaLabel: {type: String, default: 'List filters'},
    filterInputId: {type: String, default: 'cavil-list-filter-input'},
    filterLabel: {type: String, default: 'Filter'},
    filterPlaceholder: {type: String, default: 'Filter'},
    pageTitle: {type: String, default: ''},
    plural: {type: String, required: true},
    singular: {type: String, required: true},
    start: {type: Number, required: true},
    total: {type: Number, required: true},
    totalPages: {type: Number, required: true},
    countIcon: {type: String, default: 'fa-regular fa-circle-dot'}
  },
  emits: ['filter-submit', 'goto-page', 'update:filter']
};
</script>

<style>
.cavil-list-page {
  color: #24292f;
  font-size: 0.875rem;
  line-height: 1.5;
}

.cavil-list-page-heading {
  border-bottom: 1px solid #d8dee4;
  margin-bottom: 1rem;
  padding-bottom: 0.6rem;
}

.cavil-list-page-heading h2 {
  color: #24292f;
  font-size: 1.25rem;
  font-weight: 600;
  line-height: 1.3;
  margin: 0;
}

.cavil-list-toolbar {
  align-items: center;
  background: transparent;
  border: 0;
  display: flex;
  gap: 0.75rem;
  justify-content: space-between;
  margin-bottom: 1rem;
}

.cavil-list-controls {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.cavil-list-actions {
  align-items: center;
  display: flex;
  flex: 1 1 auto;
  flex-wrap: wrap;
  gap: 0.5rem;
  justify-content: flex-start;
  min-width: 0;
}

.cavil-list-per-page {
  align-items: center;
  display: flex;
  margin-left: auto;
}

.cavil-list-control {
  align-items: center;
  display: flex;
  gap: 0.4rem;
}

.cavil-list-control span {
  color: #57606a;
  font-size: 0.875rem;
  font-weight: 500;
  white-space: nowrap;
}

.cavil-list-control .form-select {
  background-color: #f6f8fa;
  border-color: #d0d7de;
  border-radius: 6px;
  color: #24292f;
  font-size: 0.875rem;
  min-height: 32px;
  min-width: 4.75rem;
  padding-bottom: 0.25rem;
  padding-top: 0.25rem;
}

.cavil-list-check {
  align-items: center;
  display: inline-flex;
  gap: 0.45rem;
  min-height: 32px;
  padding: 0 0.25rem;
}

.cavil-list-check .form-check-input {
  float: none;
  margin: 0;
}

.cavil-list-check label {
  color: #57606a;
  font-size: 0.875rem;
  font-weight: 500;
  margin: 0;
  white-space: nowrap;
}

.cavil-list-toggle {
  align-items: center;
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-radius: 999px;
  color: #57606a;
  display: inline-flex;
  font-size: 0.8125rem;
  font-weight: 600;
  gap: 0.35rem;
  line-height: 1.25;
  min-height: 28px;
  padding: 0.25rem 0.6rem;
  white-space: nowrap;
}

.cavil-list-toggle:hover,
.cavil-list-toggle:focus {
  background: #eef2f5;
  border-color: #afb8c1;
  color: #24292f;
}

.cavil-list-toggle:focus {
  box-shadow: 0 0 0 3px #0969da33;
  outline: none;
}

.cavil-list-toggle.is-active {
  background: #ddf4ff;
  border-color: #54aeff;
  color: #0969da;
}

.cavil-list-toggle i {
  font-size: 0.75rem;
}

#cavil-pkg-filter {
  flex: 1 1 20rem;
  margin: 0;
  min-width: min(20rem, 100%);
  white-space: nowrap;
}

.cavil-list-filter label {
  border: 0;
  clip: rect(0, 0, 0, 0);
  height: 1px;
  margin: -1px;
  overflow: hidden;
  padding: 0;
  position: absolute;
  white-space: nowrap;
  width: 1px;
}

.cavil-list-filter-box {
  align-items: center;
  display: flex;
  position: relative;
}

.cavil-list-filter-box i {
  color: #6e7781;
  left: 0.75rem;
  position: absolute;
}

.cavil-list-filter-box input {
  border-color: #d0d7de;
  border-radius: 6px;
  font-size: 0.875rem;
  min-height: 32px;
  padding-left: 2.1rem;
}

.cavil-list-filter-box input:focus,
.cavil-list-control .form-select:focus {
  border-color: #0969da;
  box-shadow: inset 0 0 0 1px #0969da;
}

.cavil-list-panel {
  background: #fff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  overflow: hidden;
}

.cavil-list-header {
  align-items: center;
  background: #f6f8fa;
  border-bottom: 1px solid #d8dee4;
  display: flex;
  gap: 1rem;
  justify-content: space-between;
  padding: 0.55rem 0.75rem;
}

.cavil-list-title {
  align-items: center;
  color: #24292f;
  display: inline-flex;
  gap: 0.35rem;
  font-size: 0.875rem;
  line-height: 1.4;
}

.cavil-list-title i {
  color: #1a7f37;
}

.cavil-list-title strong {
  font-weight: 600;
}

.cavil-list-table-wrap {
  overflow-x: auto;
}

.cavil-list-table.table {
  margin: 0;
}

.cavil-list-table thead th {
  background: #fff;
  border-bottom: 1px solid #d8dee4;
  color: #57606a;
  font-size: 0.8125rem;
  font-weight: 600;
  padding: 0.5rem 0.75rem;
  white-space: nowrap;
}

.cavil-list-table tbody td {
  border-color: #d8dee4;
  font-size: 0.875rem;
  padding: 0.7rem 0.75rem;
  vertical-align: middle;
}

.cavil-list-table tbody tr:last-child td {
  border-bottom: 0;
}

.cavil-list-priority {
  text-align: center;
  width: 1%;
}

.cavil-list-table tbody td.cavil-list-link {
  color: #6e7781;
  font-size: 0.8125rem;
  font-weight: 400;
  min-width: min(10rem, 22vw);
  max-width: 18rem;
  overflow-wrap: break-word;
}

.cavil-list-table a {
  text-decoration: none;
}

.cavil-list-link a {
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  color: #57606a;
  display: inline-block;
  font-family: ui-monospace, SFMono-Regular, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 0.8125rem;
  line-height: 1.35;
  padding: 0.1rem 0.4rem;
}

.cavil-list-token {
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  color: #57606a;
  display: inline-block;
  font-family: ui-monospace, SFMono-Regular, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 0.8125rem;
  line-height: 1.35;
  padding: 0.1rem 0.4rem;
}

.cavil-list-link a:hover,
.cavil-list-link a:focus,
.cavil-list-package a:hover,
.cavil-list-package a:focus {
  color: #0969da;
}

.cavil-list-link a:hover,
.cavil-list-link a:focus {
  background: #ddf4ff;
  border-color: #54aeff66;
}

.cavil-list-package a,
.cavil-list-primary a,
.cavil-list-report a {
  color: #0969da;
  font-weight: 600;
}

.cavil-list-package a:hover,
.cavil-list-package a:focus,
.cavil-list-primary a:hover,
.cavil-list-primary a:focus,
.cavil-list-report a:hover,
.cavil-list-report a:focus {
  color: #0550ae;
}

.cavil-list-table a:hover,
.cavil-list-table a:focus {
  text-decoration: underline;
}

.cavil-list-table tbody td.cavil-list-time {
  color: #6e7781;
  font-size: 0.8125rem;
  font-weight: 400;
  letter-spacing: 0;
  white-space: nowrap;
}

.cavil-list-comment {
  max-width: 24rem;
}

.cavil-list-comment-body {
  background: #f6f8fa;
  border-left: 3px solid #d0d7de;
  border-radius: 6px;
  color: #57606a;
  display: inline-block;
  font-size: 0.8125rem;
  line-height: 1.45;
  max-width: 24rem;
  overflow-wrap: anywhere;
  padding: 0.45rem 0.6rem;
}

.cavil-list-state {
  color: #57606a;
  font-weight: 600;
  height: 6rem;
  text-align: center;
}

.cavil-list-state i {
  margin-right: 0.35rem;
}

.cavil-list-empty-cell {
  padding: 0 !important;
}

.cavil-list-footer {
  align-items: center;
  background: transparent;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  justify-content: center;
  margin-top: 0.85rem;
  padding: 0 0 0.5rem;
}

#cavil-pagination {
  margin: 0;
  white-space: nowrap;
}

#cavil-pagination ul {
  justify-content: center;
  margin: 0;
  white-space: nowrap;
}

.cavil-list-footer #cavil-pagination .pagination {
  gap: 0.15rem;
}

.cavil-list-footer #cavil-pagination .page-link {
  align-items: center;
  background: transparent;
  border: 1px solid transparent;
  border-radius: 6px;
  color: #0969da;
  display: inline-flex;
  font-size: 0.875rem;
  justify-content: center;
  line-height: 1.25;
  min-width: 2rem;
  min-height: 2rem;
  padding: 0.35rem 0.6rem;
  text-align: center;
}

.cavil-list-footer #cavil-pagination .page-link:hover,
.cavil-list-footer #cavil-pagination .page-link:focus {
  background: #ddf4ff;
  color: #0550ae;
  box-shadow: none;
}

.cavil-list-footer #cavil-pagination .page-item.active .page-link {
  background: #0969da;
  border-color: #0969da;
  color: #fff;
  font-weight: 600;
}

.cavil-list-footer #cavil-pagination .page-item.disabled .page-link {
  background: transparent;
  color: #8c959f;
}

@media (max-width: 767.98px) {
  .cavil-list-toolbar,
  .cavil-list-header,
  .cavil-list-footer {
    align-items: stretch;
    flex-direction: column;
  }

  .cavil-list-controls,
  .cavil-list-actions,
  .cavil-list-per-page,
  #cavil-pkg-filter {
    width: 100%;
  }

  .cavil-list-per-page {
    margin-left: 0;
  }

  .cavil-list-control,
  .cavil-list-control .form-select {
    flex: 1 1 9rem;
  }
}
</style>
