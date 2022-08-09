<template>
  <ul class="pagination">
    <li v-if="currentPage > 1">
      <a href="#" class="page-link" @click="$emit('goto-page', 1)">First</a>
    </li>
    <li v-else class="page-item disabled">
      <a class="page-link">First</a>
    </li>

    <li v-if="start > 1" class="page-item">
      <a href="#" class="page-link" @click.stop="$emit('goto-page', currentPage - 1)">Previous</a>
    </li>
    <li v-else class="page-item disabled">
      <a class="page-link">Previous</a>
    </li>

    <li v-if="currentPage - 1 > 1" class="page-item">
      <a href="#" class="page-link" @click="$emit('goto-page', currentPage - 2)">{{ currentPage - 2 }}</a>
    </li>
    <li v-if="currentPage > 1" class="page-item">
      <a href="#" class="page-link" @click="$emit('goto-page', currentPage - 1)">{{ currentPage - 1 }}</a>
    </li>
    <li class="page-item active">
      <a href="#" class="page-link" @click="$emit('goto-page', currentPage)">{{ currentPage }}</a>
    </li>
    <li v-if="totalPages > currentPage" class="page-item">
      <a href="#" class="page-link" @click="$emit('goto-page', currentPage + 1)">{{ currentPage + 1 }}</a>
    </li>
    <li v-if="totalPages > currentPage + 1" class="page-item">
      <a href="#" class="page-link" @click="$emit('goto-page', currentPage + 2)">{{ currentPage + 2 }}</a>
    </li>

    <li v-if="end < total" class="page-item next">
      <a href="#" class="page-link" @click.stop="$emit('goto-page', currentPage + 1)">Next</a>
    </li>
    <li v-else class="page-item disabled">
      <a class="page-link">Next</a>
    </li>

    <li v-if="currentPage < totalPages">
      <a href="#" class="page-link" @click="$emit('goto-page', totalPages)">Last</a>
    </li>
    <li v-else class="page-item disabled">
      <a class="page-link">Last</a>
    </li>
  </ul>
</template>

<script>
export default {
  name: 'PaginationLinks',
  props: {
    currentPage: {type: Number, required: true},
    end: {type: Number, required: true},
    start: {type: Number, required: true},
    total: {type: Number, required: true},
    totalPages: {type: Number, required: true}
  }
};
</script>

<style>
#cavil-pagination {
  margin: 0;
  white-space: nowrap;
  text-align: right;
}
#cavil-pagination ul {
  margin: 2px 0;
  white-space: nowrap;
  justify-content: flex-end;
}
</style>
