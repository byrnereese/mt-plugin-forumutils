<?php
function smarty_function_mtentrywaspromoted($args, &$ctx) {
  $entry = $ctx->stash('entry');
  return $entry['promoted_from_comment_id'] > 0 ? 1 : 0;
}
?> 

