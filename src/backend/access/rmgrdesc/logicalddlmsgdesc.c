/*-------------------------------------------------------------------------
 *
 * logicalddlmsgdesc.c
 *	  rmgr descriptor routines for replication/logical/ddlmessage.c
 *
 * Portions Copyright (c) 2015-2022, PostgreSQL Global Development Group
 *
 *
 * IDENTIFICATION
 *	  src/backend/access/rmgrdesc/logicalddlmsgdesc.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "replication/ddlmessage.h"

void
logicalddlmsg_desc(StringInfo buf, XLogReaderState *record)
{
	char	   *rec = XLogRecGetData(record);
	uint8		info = XLogRecGetInfo(record) & ~XLR_INFO_MASK;

	if (info == XLOG_LOGICAL_DDL_MESSAGE)
	{
		xl_logical_ddl_message *xlrec = (xl_logical_ddl_message *) rec;
		char	   *prefix = xlrec->message;
		char       *role = xlrec->message + xlrec->prefix_size;
		char       *search_path = xlrec->message + xlrec->prefix_size + xlrec->role_size;
		char	   *message = xlrec->message + xlrec->prefix_size + xlrec->role_size + xlrec->search_path_size;
		char	   *sep = "";

		Assert(prefix[xlrec->prefix_size] != '\0');

		appendStringInfo(buf, "prefix \"%s\"; role \"%s\"; search_path \"%s\"; payload (%zu bytes): ",
						 prefix, role, search_path, xlrec->message_size);
		/* Write message payload as a series of hex bytes */
		for (int cnt = 0; cnt < xlrec->message_size; cnt++)
		{
			appendStringInfo(buf, "%s%02X", sep, (unsigned char) message[cnt]);
			sep = " ";
		}
	}
}

const char *
logicalddlmsg_identify(uint8 info)
{
	if ((info & ~XLR_INFO_MASK) == XLOG_LOGICAL_DDL_MESSAGE)
		return "DDL MESSAGE";

	return NULL;
}
